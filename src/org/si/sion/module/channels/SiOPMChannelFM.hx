//----------------------------------------------------------------------------------------------------
// SiOPM FM channel.
//  Copyright (c) 2008 keim All rights reserved.
//  Distributed under BSD-style license (see org.si.license.txt).
//----------------------------------------------------------------------------------------------------

package org.si.sion.module.channels;


import org.si.utils.SLLNumber;
import org.si.utils.SLLint;
import org.si.sion.module.*;


/** FM sound channel. 
 *  <p>
 *  The calculation of this class is based on OPM emulation (refer from sources of mame, fmgen and x68sound).
 *  And it has some extension to simulate other sevral fm sound modules (OPNA, OPLL, OPL2, OPL3, OPX, MA3, MA5, MA7, TSS and DX7).
 *  <ul>
 *    <li>steleo output (from TSS,DX7)</li>
 *    <li>key scale level (from OPL3,OPX,MAx)</li>
 *    <li>phase select (from TSS)</li>
 *    <li>fixed frequency (from MAx)</li>
 *    <li>ssgec (from OPNA)</li>
 *    <li>wave shape select (from OPX,MAx,TSS)</li>
 *    <li>custom wave shape (from MAx)</li>
 *    <li>some more algolisms (from OPLx,OPX,MAx,DX7)</li>
 *    <li>decimal multiple (from p-TSS)</li>
 *    <li>feedback from op1-3 (from DX7)</li>
 *    <li>channel independet LFO (from TSS)</li>
 *    <li>low-pass filter envelop (from MAx)</li>
 *    <li>flexible fm connections (from TSS)</li>
 *    <li>ring modulation (from C64?)</li>
 *  </ul>
 *  </p>
 */
class SiOPMChannelFM extends SiOPMChannelBase
{
    // constants
    //--------------------------------------------------
    private static inline var PROC_OP1 : Int = 0;
    private static inline var PROC_OP2 : Int = 1;
    private static inline var PROC_OP3 : Int = 2;
    private static inline var PROC_OP4 : Int = 3;
    private static inline var PROC_ANA : Int = 4;
    private static inline var PROC_RNG : Int = 5;
    private static inline var PROC_SYN : Int = 6;
    private static inline var PROC_AFM : Int = 7;
    private static inline var PROC_PCM : Int = 8;
    private static inline var INT_MIN_VALUE = -2147483648;




    // valiables
    //--------------------------------------------------
    /** eg_out threshold to check idling */private static var idlingThreshold : Int = 5120;  // = 256(resolution)*10(2^10=1024)*2(p/n) = volume<1/1024  
    
    // Operators
    /** operators */public var operator : Array<SiOPMOperator>;
    /** active operator */public var activeOperator : SiOPMOperator;
    
    // Parameters
    /** count */private var _operatorCount : Int;
    /** algorism */private var _algorism : Int;
    
    // Processing
    /** process func */private var _funcProcessList : Array<Dynamic>;
    /** process type */private var _funcProcessType : Int;
    
    // Pipe
    /** internal pipe0 */private var _pipe0 : SLLint;
    /** internal pipe1 */private var _pipe1 : SLLint;
    
    // modulation
    /** am depth */private var _am_depth : Int;  // = chip.amd<<(ams-1)  
    /** am output level */private var _am_out : Int;
    /** pm depth */private var _pm_depth : Int;  // = chip.pmd<<(pms-1)  
    /** pm output level */private var _pm_out : Int;
    
    
    // tone generator setting
    /** ENV_TIMER_INITIAL * freq_ratio */private var _eg_timer_initial : Int;
    /** LFO_TIMER_INITIAL * freq_ratio */private var _lfo_timer_initial : Int;
    
    /** register map type */
    private var registerMapType : Int;
    private var registerMapChannel : Int;
    
    
    
    // toString
    //--------------------------------------------------
    /** Output parameters. */
    public function toString() : String
    {
        var str : String = "SiOPMChannelFM : operatorCount=";

        function dlr(p : String, i : Dynamic) : Void{str += "  " + p + "=" + Std.string(i) + "\n";
        };
        function dlr2(p : String, i : Dynamic, q : String, j : Dynamic) : Void{str += "  " + p + "=" + Std.string(i) + " / " + q + "=" + Std.string(j) + "\n";
        };

        str += Std.string(_operatorCount) + "\n";
        dlr("fb ", _inputLevel - 6);
        dlr2("vol", _volumes[0], "pan", _pan - 64);
        if (operator[0] != null) str += Std.string(operator[0]) + "\n";
        if (operator[1] != null) str += Std.string(operator[1]) + "\n";
        if (operator[2] != null) str += Std.string(operator[2]) + "\n";
        if (operator[3] != null) str += Std.string(operator[3]) + "\n";
        return str;
    }

    // constructor
    //--------------------------------------------------
    /** constructor */
    public function new(chip : SiOPMModule)
    {
        super(chip);

        _funcProcessList = [[_proc1op_loff, _proc2op, _proc3op, _proc4op, _proc2ana, _procring, _procsync, _proc2op, _procpcm_loff],
                [_proc1op_lon, _proc2op, _proc3op, _proc4op, _proc2ana, _procring, _procsync, _proc2op, _procpcm_lon]];
        operator = new Array<SiOPMOperator>();
        operator[0] = _allocFMOperator();
        operator[1] = null;
        operator[2] = null;
        operator[3] = null;
        activeOperator = operator[0];
        
        _operatorCount = 1;
        _funcProcessType = PROC_OP1;
        _funcProcess = _proc1op_loff;

        _pipe0 = SLLint.allocRing(1);
        _pipe1 = SLLint.allocRing(1);

        initialize(null, 0);
    }
    

    // Chip settings
    //--------------------------------------------------
    /** set chip "PSEUDO" frequency ratio by [%]. 100 means 3.56MHz. This value effects only for envelop and lfo speed. */
    override public function setFrequencyRatio(ratio : Int) : Void
    {
        _freq_ratio = ratio;
        var r : Float = ((ratio != 0)) ? (100 / ratio) : 1;
        _eg_timer_initial = Math.floor(SiOPMTable.ENV_TIMER_INITIAL * r);
        _lfo_timer_initial = Math.floor(SiOPMTable.LFO_TIMER_INITIAL * r);
    }
    
    
    
    
    // LFO settings
    //--------------------------------------------------
    /** initialize low frequency oscillator. and stop lfo
     *  @param waveform LFO waveform. 0=saw, 1=pulse, 2=triangle, 3=noise. -1 to set customized wave table
     *  @param customWaveTable customized wave table, the length is 256 and the values are limited in the range of 0-255. This argument is available when waveform=-1.
     */
    override public function initializeLFO(waveform : Int, customWaveTable : Array<Int> = null) : Void
    {
        super.initializeLFO(waveform, customWaveTable);
        _lfoSwitch(false);
        _am_depth = 0;
        _pm_depth = 0;
        _am_out = 0;
        _pm_out = 0;
        if (operator[0] != null) operator[0].detune2 = 0;
        if (operator[1] != null) operator[1].detune2 = 0;
        if (operator[2] != null) operator[2].detune2 = 0;
        if (operator[3] != null) operator[3].detune2 = 0;
    }
    
    
    /** Amplitude modulation.
     *  @param depth depth = (ams) ? (amd &lt;&lt; (ams-1)) : 0;
     */
    override public function setAmplitudeModulation(depth : Int) : Void
    {
        _am_depth = depth << 2;
        _am_out = (_lfo_waveTable[_lfo_phase] * _am_depth) >> 7 << 3;
        _lfoSwitch(_pm_depth != 0 || _am_depth > 0);
    }
    
    
    /** Pitch modulation.
     *  @param depth depth = (pms&lt;6) ? (pmd &gt;&gt; (6-pms)) : (pmd &lt;&lt; (pms-5));
     */
    override public function setPitchModulation(depth : Int) : Void
    {
        _pm_depth = depth;
        _pm_out = (((_lfo_waveTable[_lfo_phase] << 1) - 255) * _pm_depth) >> 8;
        _lfoSwitch(_pm_depth != 0 || _am_depth > 0);
        if (_pm_depth == 0) {
            if (operator[0] != null) operator[0].detune2 = 0;
            if (operator[1] != null) operator[1].detune2 = 0;
            if (operator[2] != null) operator[2].detune2 = 0;
            if (operator[3] != null) operator[3].detune2 = 0;
        }
    }
    
    
    /** @private [protected] lfo on/off */
    private function _lfoSwitch(sw : Bool) : Void
    {
        _lfo_on = sw ? 1 : 0;
        _funcProcess = _funcProcessList[_lfo_on][_funcProcessType];
        _lfo_timer_step = sw ? _lfo_timer_step_ : 0;
    }
    
    
    
    
    // parameter setting
    //--------------------------------------------------
    /** Set by SiOPMChannelParam. 
     *  @param param SiOPMChannelParam.
     *  @param withVolume Set volume when its true.
     *  @param withModulation Set modulation when its true.
     */
    override public function setSiOPMChannelParam(param : SiOPMChannelParam, withVolume : Bool, withModulation : Bool = true) : Void
    {
        var i : Int;
        if (param.opeCount == 0)             return;
        
        if (withVolume) {
            var imax : Int = SiOPMModule.STREAM_SEND_SIZE;
            for (i in 0...imax){
                _volumes[i] = param.volumes[i];
            }
            _hasEffectSend=false;
            for (i in 1...imax){
                if (_volumes[i] > 0) _hasEffectSend = true;
            }
            _pan = param.pan;
        }
        setFrequencyRatio(param.fratio);
        setAlgorism(param.opeCount, param.alg);
        setFeedBack(param.fb, param.fbc);
        if (withModulation) {
            initializeLFO(param.lfoWaveShape);
            _lfo_timer = ((param.lfoFreqStep > 0)) ? 1 : 0;
            _lfo_timer_step_ = _lfo_timer_step = param.lfoFreqStep;
            setAmplitudeModulation(param.amd);
            setPitchModulation(param.pmd);
        }
        filterType = param.filterType;
        setSVFilter(param.cutoff, param.resonance, param.far, param.fdr1, param.fdr2, param.frr, param.fdc1, param.fdc2, param.fsc, param.frc);
        for (i in 0..._operatorCount){
            operator[i].setSiOPMOperatorParam(param.operatorParam[i]);
        }
    }
    
    
    /** Get SiOPMChannelParam.
     *  @param param SiOPMChannelParam.
     */
    override public function getSiOPMChannelParam(param : SiOPMChannelParam) : Void
    {
        var i : Int;
        var imax : Int = SiOPMModule.STREAM_SEND_SIZE;
        for (i in 0...imax){param.volumes[i] = _volumes[i];
        }
        param.pan = _pan;
        param.fratio = _freq_ratio;
        param.opeCount = _operatorCount;
        param.alg = _algorism;
        param.fb = 0;
        param.fbc = 0;
        for (i in 0..._operatorCount){
            if (_inPipe == operator[i]._feedPipe) {
                param.fb = _inputLevel - 6;
                param.fbc = i;
                break;
            }
        }
        param.lfoWaveShape = _lfo_waveShape;
        param.lfoFreqStep = _lfo_timer_step_;
        param.amd = _am_depth;
        param.pmd = _pm_depth;
        for (i in 0..._operatorCount){
            operator[i].getSiOPMOperatorParam(param.operatorParam[i]);
        }
    }
    
    
    /** Set sound by 14 basic params. The value of int.MIN_VALUE means not to change.
     *  @param ar Attack rate [0-63].
     *  @param dr Decay rate [0-63].
     *  @param sr Sustain rate [0-63].
     *  @param rr Release rate [0-63].
     *  @param sl Sustain level [0-15].
     *  @param tl Total level [0-127].
     *  @param ksr Key scaling [0-3].
     *  @param ksl key scale level [0-3].
     *  @param mul Multiple [0-15].
     *  @param dt1 Detune 1 [0-7]. 
     *  @param detune Detune.
     *  @param ams Amplitude modulation shift [0-3].
     *  @param phase Phase [0-255].
     *  @param fixNote Fixed note number [0-127].
     */
    public function setSiOPMParameters(ar : Int, dr : Int, sr : Int, rr : Int, sl : Int, tl : Int, ksr : Int, ksl : Int, mul : Int, dt1 : Int, detune : Int, ams : Int, phase : Int, fixNote : Int) : Void
    {
        var ope : SiOPMOperator = activeOperator;
        if (ar      != INT_MIN_VALUE) ope.ar = ar;
        if (dr      != INT_MIN_VALUE) ope.dr = dr;
        if (sr      != INT_MIN_VALUE) ope.sr = sr;
        if (rr      != INT_MIN_VALUE) ope.rr = rr;
        if (sl      != INT_MIN_VALUE) ope.sl = sl;
        if (tl      != INT_MIN_VALUE) ope.tl = tl;
        if (ksr     != INT_MIN_VALUE) ope.ks = ksr;
        if (ksl     != INT_MIN_VALUE) ope.ksl = ksl;
        if (mul     != INT_MIN_VALUE) ope.mul = mul;
        if (dt1     != INT_MIN_VALUE) ope.dt1 = dt1;
        if (detune  != INT_MIN_VALUE) ope.detune = detune;
        if (ams     != INT_MIN_VALUE) ope.ams = ams;
        if (phase   != INT_MIN_VALUE) ope.keyOnPhase = phase;
        if (fixNote != INT_MIN_VALUE) ope.fixedPitchIndex = fixNote << 6;
    }
    
    
    /** Set wave data. 
     *  @param pcmData SiOPMWavePCMTable to set.
     */
    override public function setWaveData(waveData : SiOPMWaveBase) : Void
    {
        var pcmData : SiOPMWavePCMData = try cast(waveData, SiOPMWavePCMData) catch(e:Dynamic) null;
        if (Std.is(waveData, SiOPMWavePCMTable))  pcmData = (try cast(waveData, SiOPMWavePCMTable) catch(e:Dynamic) null)._table[60];
        
        if (pcmData != null && (pcmData.wavelet != null)) {
            _updateOperatorCount(1);
            _funcProcessType = PROC_PCM;
            _funcProcess = _funcProcessList[_lfo_on][_funcProcessType];
            activeOperator.setPCMData(pcmData);
            erst = true;
        }
        else 
        if (Std.is(waveData, SiOPMWaveTable)) {
            var waveTable : SiOPMWaveTable = try cast(waveData, SiOPMWaveTable) catch(e:Dynamic) null;
            if (waveTable.wavelet != null) {
                operator[0].setWaveTable(waveTable);
                if (operator[1] != null) operator[1].setWaveTable(waveTable);
                if (operator[2] != null) operator[2].setWaveTable(waveTable);
                if (operator[3] != null) operator[3].setWaveTable(waveTable);
            }
        }
    }
    
    
    /** set channel number (2nd argument of %) */
    override public function setChannelNumber(channelNum : Int) : Void
    {
        registerMapChannel = channelNum;
    }
    
    
    /** set register */
    override public function setRegister(addr : Int, data : Int) : Void
    {
        switch (registerMapType)
        {
            case 0:
                _setByOPMRegister(addr, data);
            case 1:
                _setBy2A03Register(addr, data);
            default:
                _setBy2A03Register(addr, data);
        }
    }
    
    
    // 2A03 register value
    private function _setBy2A03Register(addr : Int, data : Int) : Void
    {
        
    }
    
    
    // OPM register value
    private var _pmd : Int = 0;private var _amd : Int = 0;
    private function _setByOPMRegister(addr : Int, data : Int) : Void
    {
        var i : Int;
        var v : Int;
        var pms : Int;
        var ams : Int;
        var op : SiOPMOperator;
        var channel : Int = registerMapChannel;
        
        if (addr < 0x20) {  // Module parameter  
            switch (addr)
            {
                case 15:  // NOIZE:7 FREQ:4-0 for channel#7  
                if (channel == 7 && _operatorCount == 4 && (data & 128) != 0) {
                    operator[3].pgType = SiOPMTable.PG_NOISE_PULSE;
                    operator[3].ptType = SiOPMTable.PT_OPM_NOISE;
                    operator[3].pitchIndex = ((data & 31) << 6) + 2048;
                }
                case 24:  // LFO FREQ:7-0 for all 8 channels  
                    v = _table.lfo_timerSteps[data];
                    _lfo_timer = ((v > 0)) ? 1 : 0;
                    _lfo_timer_step_ = _lfo_timer_step = v;
                case 25:  // A(0)/P(1):7 DEPTH:6-0 for all 8 channels  
                if ((data & 128) != 0) _amd = data & 127
                else _pmd = data & 127;
                case 27:  // LFO WS:10 for all 8 channels  
                initializeLFO(data & 3);
            }
        }
        else {
            if (channel == (addr & 7)) {
                if (addr < 0x40) {
                    // Channel parameter
                    var _sw0_ = ((addr - 0x20) >> 3);                    

                    switch (_sw0_)
                    {
                        case 0:  // L:7 R:6 FB:5-3 ALG:2-0  
                            v = data >> 6;
                            setAlgorism(4, data & 7);
                            setFeedBack((data >> 3) & 7, 0);
                            _volumes[0] = ((v != 0)) ? 0.5 : 0;
                            _pan = ((v == 1)) ? 128 : ((v == 2)) ? 0 : 64;
                        case 1:  // KC:6-0  
                        for (i in 0...4) {
                            operator[i].kc = data & 127;
                        }
                        case 2:  // KF:6-0  
                        for (i in 0...4) {
                            operator[i].kf = data & 127;
                        }
                        case 3:  // PMS:6-4 AMS:10  
                            pms = (data >> 4) & 7;
                            ams = (data) & 3;
                            if ((data & 128) != 0) setPitchModulation(((pms < 6)) ? (_pmd >> (6 - pms)) : (_pmd << (pms - 5)))
                            else setAmplitudeModulation(((ams > 0)) ? (_amd << (ams - 1)) : 0);
                    }
                }
                else {
                    // Operator parameter
                    op = operator[[0, 2, 1, 3][(addr >> 3) & 3]];  // [3,1,2,0]  
                    var _sw1_ = ((addr - 0x40) >> 5);                    

                    switch (_sw1_)
                    {
                        case 0:  // DT1:6-4 MUL:3-0  
                            op.dt1 = (data >> 4) & 7;
                            op.mul = (data) & 15;
                        case 1:  // TL:6-0  
                        op.tl = data & 127;
                        case 2:  // KS:76 AR:4-0  
                            op.ks = (data >> 6) & 3;
                            op.ar = (data & 31) << 1;
                        case 3:  // AMS:7 DR:4-0  
                            op.ams = ((data >> 7) & 1) << 1;
                            op.dr = (data & 31) << 1;
                        case 4:  // DT2:76 SR:4-0  
                            op.detune = [0, 384, 500, 608][(data >> 6) & 3];
                            op.sr = (data & 31) << 1;
                        case 5:  // SL:7-4 RR:3-0  
                            op.sl = (data >> 4) & 15;
                            op.rr = (data & 15) << 2;
                    }
                }
            }
        }
    }
    
    
    
    
    // interfaces
    //--------------------------------------------------
    /** Set algorism (&#64;al) 
     *  @param cnt Operator count.
     *  @param alg Algolism number of the operator's connection.
     */
    override public function setAlgorism(cnt : Int, alg : Int) : Void
    {
        switch (cnt)
        {
            case 2:_algorism2(alg);
            case 3:_algorism3(alg);
            case 4:_algorism4(alg);
            case 5:_analog(alg);
            default:_algorism1(alg);
        }
    }
    
    
    /** Set feedback(&#64;fb). This also initializes the input mode(&#64;i). 
     *  @param fb Feedback level. Ussualy in the range of 0-7.
     *  @param fbc Feedback connection. Operator index which feeds back its output.
     */
    override public function setFeedBack(fb : Int, fbc : Int) : Void
    {
        if (fb > 0) {
            // connect feedback pipe
            if (fbc < 0 || fbc >= _operatorCount)                 fbc = 0;
            _inPipe = operator[fbc]._feedPipe;
            _inPipe.i = 0;
            _inputLevel = fb + 6;
            _inputMode = INPUT_FEEDBACK;
        }
        else {
            // no feedback
            _inPipe = _chip.zeroBuffer;
            _inputLevel = 0;
            _inputMode = INPUT_ZERO;
        }
    }
    
    
    /** Set parameters (&#64; command). */
    override public function setParameters(param : Array<Int>) : Void
    {
        setSiOPMParameters(param[1], param[2], param[3], param[4], param[5],
                param[6], param[7], param[8], param[9], param[10],
                param[11], param[12], param[13], param[14]);
    }
    
    
    /** pgType and ptType (&#64;) */
    override public function setType(pgType : Int, ptType : Int) : Void
    {
        if (pgType >= SiOPMTable.PG_PCM) {
            var pcm : SiOPMWavePCMTable = _table.getPCMData(pgType - SiOPMTable.PG_PCM);
            // the ptType is set by setWaveData()
            if (pcm != null)                 setWaveData(pcm);
        }
        else {
            activeOperator.pgType = pgType;
            activeOperator.ptType = ptType;
            _funcProcess = _funcProcessList[_lfo_on][_funcProcessType];
        }
    }
    
    
    /** Attack rate */
    override public function setAllAttackRate(ar : Int) : Void
    {
        var i : Int;
        var ope : SiOPMOperator;
        for (i in 0..._operatorCount){
            ope = operator[i];
            if (ope._final)                 ope.ar = ar;
        }
    }
    
    
    /** Release rate (s) */
    override public function setAllReleaseRate(rr : Int) : Void
    {
        var i : Int;
        var ope : SiOPMOperator;
        for (i in 0..._operatorCount){
            ope = operator[i];
            if (ope._final)                 ope.rr = rr;
        }
    }
    
    
    // interfaces
    //--------------------------------------------------
    /** pitch = (note &lt;&lt; 6) | (kf &amp; 63) [0,8191] */
    override private function get_pitch() : Int{
        return operator[_operatorCount - 1].pitchIndex;
    }
    override private function set_pitch(p : Int) : Int{
        for (i in 0..._operatorCount){
            operator[i].pitchIndex = p;
        }
        return p;
    }
    
    /** active operator index (i) */
    override private function set_activeOperatorIndex(i : Int) : Int{
        var opeIndex : Int = ((i < 0)) ? 0 : ((i >= _operatorCount)) ? (_operatorCount - 1) : i;
        activeOperator = operator[opeIndex];
        return i;
    }
    
    /** release rate (&#64;rr) */
    override private function set_rr(i : Int) : Int{
        activeOperator.rr = i;
        return i;
    }
    
    /** total level (&#64;tl) */
    private function set_rl(i : Int) : Int{
        activeOperator.tl = i;
        return i;
    }
    
    /** fine multiple (&#64;ml) */
    override private function set_fmul(i : Int) : Int{
        activeOperator.fmul = i;
        return i;
    }
    
    /** phase  (&#64;ph) */
    override private function set_phase(i : Int) : Int{
        activeOperator.keyOnPhase = i;
        return i;
    }
    
    /** detune (&#64;dt) */
    override private function set_detune(i : Int) : Int{
        activeOperator.detune = i;
        return i;
    }
    
    /** fixed pitch (&#64;fx) */
    override private function set_fixedPitch(i : Int) : Int{
        activeOperator.fixedPitchIndex = i;
        return i;
    }
    
    /** ssgec (&#64;se) */
    override private function set_ssgec(i : Int) : Int{
        activeOperator.ssgec = i;
        return i;
    }
    
    /** envelop reset (&#64;er) */
    override private function set_erst(b : Bool) : Bool{
        for (i in 0..._operatorCount){operator[i].erst = b;
        }
        return b;
    }
    
    
    
    
    // volume controls
    //--------------------------------------------------
    /** update all tl offsets of final carriors */
    override public function offsetVolume(expression : Int, velocity : Int) : Void
    {
        var i : Int;
        var ope : SiOPMOperator;
        var tl : Int;
        var x : Int = expression << 1;
        tl = _expressionTable[x] + _veocityTable[velocity];
        for (i in 0..._operatorCount) {
            ope = operator[i];
            if (ope._final)                 ope._tlOffset(tl)
            else ope._tlOffset(0);
        }
    }
    
    
    
    
    // operation
    //--------------------------------------------------
    /** Initialize. */
    override public function initialize(prev : SiOPMChannelBase, bufferIndex : Int) : Void
    {
        // initialize operators
        _updateOperatorCount(1);
		
		if (operator[0] == null)
			operator[0] = _allocFMOperator();
		
        operator[0].initialize();
        _isNoteOn = false;
        registerMapType = 0;
        registerMapChannel = 0;

        // initialize sound channel
        super.initialize(prev, bufferIndex);
    }
    
    
    /** Reset. */
    override public function reset() : Void
    {
        // reset all operators
        for (i in 0..._operatorCount){
            operator[i].reset();
        }
        _isNoteOn = false;
        _isIdling = true;
    }
    
    
    /** Note on. */
    override public function noteOn() : Void
    {
        // operator note on
        for (i in 0..._operatorCount){
            operator[i].noteOn();
        }
        _isNoteOn = true;
        _isIdling = false;
        super.noteOn();
    }
    
    
    /** Note off. */
    override public function noteOff() : Void
    {
        // operator note off
        for (i in 0..._operatorCount){
            operator[i].noteOff();
        }
        _isNoteOn = false;
        super.noteOff();
    }
    
    
    /** Prepare buffering */
    override public function resetChannelBufferStatus() : Void
    {
        _bufferIndex = 0;
        
        // check idling flag
        var i : Int;
        var ope : SiOPMOperator;
        _isIdling = true;
        for (i in 0..._operatorCount){
            ope = operator[i];
            if (ope._final && (ope._eg_out < idlingThreshold || ope._eg_state == SiOPMOperator.EG_ATTACK)) {
                _isIdling = false;
                break;
            }
        }
    }
    
    
    
    
    //====================================================================================================
    // Internal uses
    //====================================================================================================
    // processing operator x1
    //--------------------------------------------------
    // without lfo_update()
    private function _proc1op_loff(len : Int) : Void
    {
        var t : Int;
        var l : Int;
        var i : Int;
        var n : Float;
        var ope : SiOPMOperator = operator[0];
        var log : Array<Int> = _table.logTable;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // eg_update();
            //----------------------------------------
            ope._eg_timer -= ope._eg_timer_step;
            if (ope._eg_timer < 0) {
                if (ope._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope._eg_incTable[ope._eg_counter];
                    if (t > 0) {
                        ope._eg_level -= 1 + (ope._eg_level >> t);
                        if (ope._eg_level <= 0)                             ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                    }
                }
                else {
                    ope._eg_level += ope._eg_incTable[ope._eg_counter];
                    if (ope._eg_level >= ope._eg_stateShiftLevel)                         ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                }
                ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                ope._eg_counter = (ope._eg_counter + 1) & 7;
                ope._eg_timer += _eg_timer_initial;
            }  //----------------------------------------    // pg_update();  
            
            
            
            
            
            ope._phase += ope._phase_step;
            t = ((ope._phase + (ip.i << _inputLevel)) & phase_filter) >> ope._waveFixedBits;
            l = ope._waveTable[t];
            l += ope._eg_out;
            t = log[l];
            ope._feedPipe.i = t;
            
            // output and increment pointers
            //----------------------------------------
            op.i = t + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    // with lfo_update()
    private function _proc1op_lon(len : Int) : Void
    {
        var t : Int;
        var l : Int;
        var i : Int;
        var n : Float;
        var ope : SiOPMOperator = operator[0];
        var log : Array<Int> = _table.logTable;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        
        for (i in 0...len){
            // lfo_update();
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  //----------------------------------------    // eg_update();  
            
            
            
            
            
            ope._eg_timer -= ope._eg_timer_step;
            if (ope._eg_timer < 0) {
                if (ope._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope._eg_incTable[ope._eg_counter];
                    if (t > 0) {
                        ope._eg_level -= 1 + (ope._eg_level >> t);
                        if (ope._eg_level <= 0)                             ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                    }
                }
                else {
                    ope._eg_level += ope._eg_incTable[ope._eg_counter];
                    if (ope._eg_level >= ope._eg_stateShiftLevel)                         ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                }
                ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                ope._eg_counter = (ope._eg_counter + 1) & 7;
                ope._eg_timer += _eg_timer_initial;
            }  //----------------------------------------    // pg_update();  
            
            
            
            
            
            ope._phase += ope._phase_step;
            t = ((ope._phase + (ip.i << _inputLevel)) & phase_filter) >> ope._waveFixedBits;
            l = ope._waveTable[t];
            l += ope._eg_out + (_am_out >> ope._ams);
            t = log[l];
            ope._feedPipe.i = t;
            
            // output and increment pointers
            //----------------------------------------
            op.i = t + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // processing operator x2
    //--------------------------------------------------
    // This inline expansion makes execution faster.
    private function _proc2op(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // clear pipes
            //----------------------------------------
            _pipe0.i = 0;
            
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  // eg_update();    //----------------------------------------    // operator[0]  
            
            
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope0._phase += ope0._phase_step;
            t = ((ope0._phase + (ip.i << _inputLevel)) & phase_filter) >> ope0._waveFixedBits;
            l = ope0._waveTable[t];
            l += ope0._eg_out + (_am_out >> ope0._ams);
            t = log[l];
            ope0._feedPipe.i = t;
            ope0._outPipe.i = t + ope0._basePipe.i;
            
            // operator[1]
            //----------------------------------------
            // eg_update();
            ope1._eg_timer -= ope1._eg_timer_step;
            if (ope1._eg_timer < 0) {
                if (ope1._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope1._eg_incTable[ope1._eg_counter];
                    if (t > 0) {
                        ope1._eg_level -= 1 + (ope1._eg_level >> t);
                        if (ope1._eg_level <= 0)                             ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                    }
                }
                else {
                    ope1._eg_level += ope1._eg_incTable[ope1._eg_counter];
                    if (ope1._eg_level >= ope1._eg_stateShiftLevel)                         ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                }
                ope1._eg_out = (ope1._eg_levelTable[ope1._eg_level] + ope1._eg_total_level) << 3;
                ope1._eg_counter = (ope1._eg_counter + 1) & 7;
                ope1._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope1._phase += ope1._phase_step;
            t = ((ope1._phase + (ope1._inPipe.i << ope1._fmShift)) & phase_filter) >> ope1._waveFixedBits;
            l = ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope1._ams);
            t = log[l];
            ope1._feedPipe.i = t;
            ope1._outPipe.i = t + ope1._basePipe.i;
            
            // output and increment pointers
            //----------------------------------------
            op.i = _pipe0.i + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // processing operator x3
    //--------------------------------------------------
    // This inline expansion makes execution faster.
    private function _proc3op(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        var ope2 : SiOPMOperator = operator[2];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // clear pipes
            //----------------------------------------
            _pipe0.i = 0;
            _pipe1.i = 0;
            
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                ope2.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  // eg_update();    //----------------------------------------    // operator[0]  
            
            
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope0._phase += ope0._phase_step;
            t = ((ope0._phase + (ip.i << _inputLevel)) & phase_filter) >> ope0._waveFixedBits;
            l = ope0._waveTable[t];
            l += ope0._eg_out + (_am_out >> ope0._ams);
            t = log[l];
            ope0._feedPipe.i = t;
            ope0._outPipe.i = t + ope0._basePipe.i;
            
            // operator[1]
            //----------------------------------------
            // eg_update();
            ope1._eg_timer -= ope1._eg_timer_step;
            if (ope1._eg_timer < 0) {
                if (ope1._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope1._eg_incTable[ope1._eg_counter];
                    if (t > 0) {
                        ope1._eg_level -= 1 + (ope1._eg_level >> t);
                        if (ope1._eg_level <= 0)                             ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                    }
                }
                else {
                    ope1._eg_level += ope1._eg_incTable[ope1._eg_counter];
                    if (ope1._eg_level >= ope1._eg_stateShiftLevel)                         ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                }
                ope1._eg_out = (ope1._eg_levelTable[ope1._eg_level] + ope1._eg_total_level) << 3;
                ope1._eg_counter = (ope1._eg_counter + 1) & 7;
                ope1._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope1._phase += ope1._phase_step;
            t = ((ope1._phase + (ope1._inPipe.i << ope1._fmShift)) & phase_filter) >> ope1._waveFixedBits;
            l = ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope1._ams);
            t = log[l];
            ope1._feedPipe.i = t;
            ope1._outPipe.i = t + ope1._basePipe.i;
            
            // operator[2]
            //----------------------------------------
            // eg_update();
            ope2._eg_timer -= ope2._eg_timer_step;
            if (ope2._eg_timer < 0) {
                if (ope2._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope2._eg_incTable[ope2._eg_counter];
                    if (t > 0) {
                        ope2._eg_level -= 1 + (ope2._eg_level >> t);
                        if (ope2._eg_level <= 0)                             ope2._eg_shiftState(ope2._eg_nextState[ope2._eg_state]);
                    }
                }
                else {
                    ope2._eg_level += ope2._eg_incTable[ope2._eg_counter];
                    if (ope2._eg_level >= ope2._eg_stateShiftLevel)                         ope2._eg_shiftState(ope2._eg_nextState[ope2._eg_state]);
                }
                ope2._eg_out = (ope2._eg_levelTable[ope2._eg_level] + ope2._eg_total_level) << 3;
                ope2._eg_counter = (ope2._eg_counter + 1) & 7;
                ope2._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope2._phase += ope2._phase_step;
            t = ((ope2._phase + (ope2._inPipe.i << ope2._fmShift)) & phase_filter) >> ope2._waveFixedBits;
            l = ope2._waveTable[t];
            l += ope2._eg_out + (_am_out >> ope2._ams);
            t = log[l];
            ope2._feedPipe.i = t;
            ope2._outPipe.i = t + ope2._basePipe.i;
            
            // output and increment pointers
            //----------------------------------------
            op.i = _pipe0.i + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // processing operator x4
    //--------------------------------------------------
    // This inline expansion makes execution faster.
    private function _proc4op(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        var ope2 : SiOPMOperator = operator[2];
        var ope3 : SiOPMOperator = operator[3];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // clear pipes
            //----------------------------------------
            _pipe0.i = 0;
            _pipe1.i = 0;
            
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                ope2.detune2 = _pm_out;
                ope3.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  // eg_update();    //----------------------------------------    // operator[0]  
            
            
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope0._phase += ope0._phase_step;
            t = ((ope0._phase + (ip.i << _inputLevel)) & phase_filter) >> ope0._waveFixedBits;
            l = ope0._waveTable[t];
            l += ope0._eg_out + (_am_out >> ope0._ams);
            t = log[l];
            ope0._feedPipe.i = t;
            ope0._outPipe.i = t + ope0._basePipe.i;
            
            // operator[1]
            //----------------------------------------
            // eg_update();
            ope1._eg_timer -= ope1._eg_timer_step;
            if (ope1._eg_timer < 0) {
                if (ope1._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope1._eg_incTable[ope1._eg_counter];
                    if (t > 0) {
                        ope1._eg_level -= 1 + (ope1._eg_level >> t);
                        if (ope1._eg_level <= 0)                             ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                    }
                }
                else {
                    ope1._eg_level += ope1._eg_incTable[ope1._eg_counter];
                    if (ope1._eg_level >= ope1._eg_stateShiftLevel)                         ope1._eg_shiftState(ope1._eg_nextState[ope1._eg_state]);
                }
                ope1._eg_out = (ope1._eg_levelTable[ope1._eg_level] + ope1._eg_total_level) << 3;
                ope1._eg_counter = (ope1._eg_counter + 1) & 7;
                ope1._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope1._phase += ope1._phase_step;
            t = ((ope1._phase + (ope1._inPipe.i << ope1._fmShift)) & phase_filter) >> ope1._waveFixedBits;
            l = ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope1._ams);
            t = log[l];
            ope1._feedPipe.i = t;
            ope1._outPipe.i = t + ope1._basePipe.i;
            
            // operator[2]
            //----------------------------------------
            // eg_update();
            ope2._eg_timer -= ope2._eg_timer_step;
            if (ope2._eg_timer < 0) {
                if (ope2._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope2._eg_incTable[ope2._eg_counter];
                    if (t > 0) {
                        ope2._eg_level -= 1 + (ope2._eg_level >> t);
                        if (ope2._eg_level <= 0)                             ope2._eg_shiftState(ope2._eg_nextState[ope2._eg_state]);
                    }
                }
                else {
                    ope2._eg_level += ope2._eg_incTable[ope2._eg_counter];
                    if (ope2._eg_level >= ope2._eg_stateShiftLevel)                         ope2._eg_shiftState(ope2._eg_nextState[ope2._eg_state]);
                }
                ope2._eg_out = (ope2._eg_levelTable[ope2._eg_level] + ope2._eg_total_level) << 3;
                ope2._eg_counter = (ope2._eg_counter + 1) & 7;
                ope2._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope2._phase += ope2._phase_step;
            t = ((ope2._phase + (ope2._inPipe.i << ope2._fmShift)) & phase_filter) >> ope2._waveFixedBits;
            l = ope2._waveTable[t];
            l += ope2._eg_out + (_am_out >> ope2._ams);
            t = log[l];
            ope2._feedPipe.i = t;
            ope2._outPipe.i = t + ope2._basePipe.i;
            
            // operator[3]
            //----------------------------------------
            // eg_update();
            ope3._eg_timer -= ope3._eg_timer_step;
            if (ope3._eg_timer < 0) {
                if (ope3._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope3._eg_incTable[ope3._eg_counter];
                    if (t > 0) {
                        ope3._eg_level -= 1 + (ope3._eg_level >> t);
                        if (ope3._eg_level <= 0)                             ope3._eg_shiftState(ope3._eg_nextState[ope3._eg_state]);
                    }
                }
                else {
                    ope3._eg_level += ope3._eg_incTable[ope3._eg_counter];
                    if (ope3._eg_level >= ope3._eg_stateShiftLevel)                         ope3._eg_shiftState(ope3._eg_nextState[ope3._eg_state]);
                }
                ope3._eg_out = (ope3._eg_levelTable[ope3._eg_level] + ope3._eg_total_level) << 3;
                ope3._eg_counter = (ope3._eg_counter + 1) & 7;
                ope3._eg_timer += _eg_timer_initial;
            }  // pg_update();  
            
            ope3._phase += ope3._phase_step;
            t = ((ope3._phase + (ope3._inPipe.i << ope3._fmShift)) & phase_filter) >> ope3._waveFixedBits;
            l = ope3._waveTable[t];
            l += ope3._eg_out + (_am_out >> ope3._ams);
            t = log[l];
            ope3._feedPipe.i = t;
            ope3._outPipe.i = t + ope3._basePipe.i;
            
            // output and increment pointers
            //----------------------------------------
            op.i = _pipe0.i + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // processing PCM
    //--------------------------------------------------
    private function _procpcm_loff(len : Int) : Void
    {
        var t : Int;
        var l : Int;
        var i : Int;
        var n : Float;
        var ope : SiOPMOperator = operator[0];
        var log : Array<Int> = _table.logTable;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;

        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        i=0;
        while (i<len) {
            // eg_update();
            //----------------------------------------
            ope._eg_timer -= ope._eg_timer_step;
            if (ope._eg_timer < 0) {
                if (ope._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope._eg_incTable[ope._eg_counter];
                    if (t > 0) {
                        ope._eg_level -= 1 + (ope._eg_level >> t);
                        if (ope._eg_level <= 0) ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                    }
                }
                else {
                    ope._eg_level += ope._eg_incTable[ope._eg_counter];
                    if (ope._eg_level >= ope._eg_stateShiftLevel) ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                }
                ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                ope._eg_counter = (ope._eg_counter + 1) & 7;
                ope._eg_timer += _eg_timer_initial;
            }

            // pg_update();
            // ----------------------------------------
            ope._phase += ope._phase_step;
            t = (ope._phase + (ip.i << _inputLevel)) >>> ope._waveFixedBits;
            if (t >= ope._pcm_endPoint) {
                if (ope._pcm_loopPoint == -1) {
                    ope._eg_shiftState(SiOPMOperator.EG_OFF);
                    ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                    while (i<len) {
                        op.i = bp.i;
                        ip = ip.next;
                        bp = bp.next;
                        op = op.next;
                        i++;
                    }
                    break;
                }
                else {
                    t -= ope._pcm_endPoint - ope._pcm_loopPoint;
                    ope._phase -= (ope._pcm_endPoint - ope._pcm_loopPoint) << ope._waveFixedBits;
                }
            }
            l = ope._waveTable[t];
            l += ope._eg_out;
            t = log[l];
            ope._feedPipe.i = t;
            
            // output and increment pointers
            //----------------------------------------
            op.i = t + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;

            i++;
        }

        // update pointers
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    private function _procpcm_lon(len : Int) : Void
    {
        var t : Int;
        var l : Int;
        var i : Int;
        var n : Float;
        var ope : SiOPMOperator = operator[0];
        var log : Array<Int> = _table.logTable;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;

        i = 0;
        while (i < len) {
            // lfo_update();
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }

            // eg_update();
            // ----------------------------------------
            ope._eg_timer -= ope._eg_timer_step;
            if (ope._eg_timer < 0) {
                if (ope._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope._eg_incTable[ope._eg_counter];
                    if (t > 0) {
                        ope._eg_level -= 1 + (ope._eg_level >> t);
                        if (ope._eg_level <= 0)                             ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                    }
                }
                else {
                    ope._eg_level += ope._eg_incTable[ope._eg_counter];
                    if (ope._eg_level >= ope._eg_stateShiftLevel)                         ope._eg_shiftState(ope._eg_nextState[ope._eg_state]);
                }
                ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                ope._eg_counter = (ope._eg_counter + 1) & 7;
                ope._eg_timer += _eg_timer_initial;
            }


            // pg_update();
            // ----------------------------------------
            ope._phase += ope._phase_step;
            t = (ope._phase + (ip.i << _inputLevel)) >>> ope._waveFixedBits;
            if (t >= ope._pcm_endPoint) {
                if (ope._pcm_loopPoint == -1) {
                    ope._eg_shiftState(SiOPMOperator.EG_OFF);
                    ope._eg_out = (ope._eg_levelTable[ope._eg_level] + ope._eg_total_level) << 3;
                    while (i < len) {
                        op.i = bp.i;
                        ip = ip.next;
                        bp = bp.next;
                        op = op.next;
                        i++;
                    }
                    break;
                }
                else {
                    t -= ope._pcm_endPoint - ope._pcm_loopPoint;
                    ope._phase -= (ope._pcm_endPoint - ope._pcm_loopPoint) << ope._waveFixedBits;
                }
            }
            l = ope._waveTable[t];
            l += ope._eg_out + (_am_out >> ope._ams);
            t = log[l];
            ope._feedPipe.i = t;
            
            // output and increment pointers
            //----------------------------------------
            op.i = t + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;

            i++;
        }

        // update pointers
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // analog like processing (w/ ring and sync)
    //--------------------------------------------------
    private function _proc2ana(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var out0 : Int;
        var out1 : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  //----------------------------------------    // envelop  
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope1._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope1._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  //----------------------------------------    // operator[0]  
            
            
            
            
            
            ope0._phase += ope0._phase_step;
            t = ((ope0._phase + (ip.i << _inputLevel)) & phase_filter) >> ope0._waveFixedBits;
            l = ope0._waveTable[t];
            l += ope0._eg_out + (_am_out >> ope0._ams);
            out0 = log[l];
            
            // operator[1] with op0s envelop and ams
            //----------------------------------------
            ope1._phase += ope1._phase_step;
            t = (ope1._phase & phase_filter) >> ope1._waveFixedBits;
            l = ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope0._ams);
            out1 = log[l];
            
            // output and increment pointers
            //----------------------------------------
            ope0._feedPipe.i = out0;
            op.i = out0 + out1 + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    private function _procring(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var out0 : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  //----------------------------------------    // envelop  
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope1._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope1._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  //----------------------------------------    // operator[0]  
            
            
            
            
            
            ope0._phase += ope0._phase_step;
            t = ((ope0._phase + (ip.i << _inputLevel)) & phase_filter) >> ope0._waveFixedBits;
            l = ope0._waveTable[t];
            
            // operator[1] with op0s envelop and ams
            //----------------------------------------
            ope1._phase += ope1._phase_step;
            t = (ope1._phase & phase_filter) >> ope1._waveFixedBits;
            l += ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope0._ams);
            out0 = log[l];
            
            // output and increment pointers
            //----------------------------------------
            ope0._feedPipe.i = out0;
            op.i = out0 + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    private function _procsync(len : Int) : Void
    {
        var i : Int;
        var t : Int;
        var out0 : Int;
        var out1 : Int;
        var l : Int;
        var n : Float;
        var phase_filter : Int = SiOPMTable.PHASE_FILTER;
        var log : Array<Int> = _table.logTable;
        var phase_overflow : Int = SiOPMTable.PHASE_MAX;
        var ope0 : SiOPMOperator = operator[0];
        var ope1 : SiOPMOperator = operator[1];
        
        // buffering
        var ip : SLLint = _inPipe;
        var bp : SLLint = _basePipe;
        var op : SLLint = _outPipe;
        for (i in 0...len){
            // lfo
            //----------------------------------------
            _lfo_timer -= _lfo_timer_step;
            if (_lfo_timer < 0) {
                _lfo_phase = (_lfo_phase + 1) & 255;
                t = _lfo_waveTable[_lfo_phase];
                _am_out = (t * _am_depth) >> 7 << 3;
                _pm_out = (((t << 1) - 255) * _pm_depth) >> 8;
                ope0.detune2 = _pm_out;
                ope1.detune2 = _pm_out;
                _lfo_timer += _lfo_timer_initial;
            }  //----------------------------------------    // envelop  
            
            
            
            
            
            ope0._eg_timer -= ope0._eg_timer_step;
            if (ope0._eg_timer < 0) {
                if (ope0._eg_state == SiOPMOperator.EG_ATTACK) {
                    t = ope0._eg_incTable[ope0._eg_counter];
                    if (t > 0) {
                        ope0._eg_level -= 1 + (ope0._eg_level >> t);
                        if (ope0._eg_level <= 0)                             ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                    }
                }
                else {
                    ope0._eg_level += ope0._eg_incTable[ope0._eg_counter];
                    if (ope0._eg_level >= ope0._eg_stateShiftLevel)                         ope0._eg_shiftState(ope0._eg_nextState[ope0._eg_state]);
                }
                ope0._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope0._eg_total_level) << 3;
                ope1._eg_out = (ope0._eg_levelTable[ope0._eg_level] + ope1._eg_total_level) << 3;
                ope0._eg_counter = (ope0._eg_counter + 1) & 7;
                ope0._eg_timer += _eg_timer_initial;
            }  //----------------------------------------    // operator[0]  
            
            
            
            
            
            ope0._phase += ope0._phase_step + (ip.i << _inputLevel);
            if (ope0._phase & phase_overflow != 0)                 ope1._phase = ope1._keyon_phase;
            ope0._phase = ope0._phase & phase_filter;
            
            // operator[1] with op0s envelop and ams
            //----------------------------------------
            ope1._phase += ope1._phase_step;
            t = (ope1._phase & phase_filter) >> ope1._waveFixedBits;
            l = ope1._waveTable[t];
            l += ope1._eg_out + (_am_out >> ope0._ams);
            out0 = log[l];
            
            // output and increment pointers
            //----------------------------------------
            ope0._feedPipe.i = out0;
            op.i = out0 + bp.i;
            ip = ip.next;
            bp = bp.next;
            op = op.next;
        }  // update pointers  
        
        
        
        _inPipe = ip;
        _basePipe = bp;
        _outPipe = op;
    }
    
    
    
    
    // internal operations
    //--------------------------------------------------
    /** @private [internal use] Update LFO. This code is only for testing. */
    @:allow(org.si.sion.module.channels)
    private function _lfo_update() : Void
    {
        _lfo_timer -= _lfo_timer_step;
        if (_lfo_timer < 0) {
            _lfo_phase = (_lfo_phase + 1) & 255;
            _am_out = (_lfo_waveTable[_lfo_phase] * _am_depth) >> 7 << 3;
            _pm_out = (((_lfo_waveTable[_lfo_phase] << 1) - 255) * _pm_depth) >> 8;
            if (operator[0] != null)                 operator[0].detune2 = _pm_out;
            if (operator[1] != null)                 operator[1].detune2 = _pm_out;
            if (operator[2] != null)                 operator[2].detune2 = _pm_out;
            if (operator[3] != null)                 operator[3].detune2 = _pm_out;
            _lfo_timer += _lfo_timer_initial;
        }
    }
    
    
    // update operator count.
    private function _updateOperatorCount(cnt : Int) : Void
    {
        var i : Int;
        
        // change operator instances
        if (_operatorCount < cnt) {
            // allocate and initialize new operators
            for (i in 0...cnt) {
                operator[i] = _allocFMOperator();
                operator[i].initialize();
            }
        }
        else 
        if (_operatorCount > cnt) {
            // free old operators
            for (i in 0..._operatorCount) {
                _freeFMOperator(operator[i]);
                operator[i] = null;
            }
        }

        // update count
        _operatorCount = cnt;
        _funcProcessType = cnt - 1;
        // select processing function
        _funcProcess = _funcProcessList[_lfo_on][_funcProcessType];
        
        // default active operator is the last one.
        activeOperator = operator[_operatorCount - 1];
        
        // reset feed back
        if (_inputMode == INPUT_FEEDBACK) {
            setFeedBack(0, 0);
        }
    }
    
    
    // alg operator=1
    private function _algorism1(alg : Int) : Void
    {
        _updateOperatorCount(1);
        _algorism = alg;
        operator[0]._setPipes(_pipe0, null, true);
    }
    
    
    // alg operator=2
    private function _algorism2(alg : Int) : Void
    {
        _updateOperatorCount(2);
        _algorism = alg;
        switch (_algorism)
        {
            case 0:  // OPL3/MA3:con=0, OPX:con=0, 1(fbc=1)  
                // o1(o0)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
            case 1:  // OPL3/MA3:con=1, OPX:con=2  
                // o0+o1
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
            case 2:  // OPX:con=3  
                // o0+o1(o0)
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[1]._basePipe = _pipe0;
            default:
                // o0+o1
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
        }
    }
    
    
    // alg operator=3
    private function _algorism3(alg : Int) : Void
    {
        _updateOperatorCount(3);
        _algorism = alg;
        switch (_algorism)
        {
            case 0:  // OPX:con=0, 1(fbc=1)  
                // o2(o1(o0))
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0);
                operator[2]._setPipes(_pipe0, _pipe0, true);
            case 1:  // OPX:con=2  
                // o2(o0+o1)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0);
                operator[2]._setPipes(_pipe0, _pipe0, true);
            case 2:  // OPX:con=3  
                // o0+o2(o1)
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe1);
                operator[2]._setPipes(_pipe0, _pipe1, true);
            case 3:  // OPX:con=4, 5(fbc=1)  
                // o1(o0)+o2
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[2]._setPipes(_pipe0, null, true);
            case 4:
                // o1(o0)+o2(o0)
                operator[0]._setPipes(_pipe1);
                operator[1]._setPipes(_pipe0, _pipe1, true);
                operator[2]._setPipes(_pipe0, _pipe1, true);
            case 5:  // OPX:con=6  
                // o0+o1+o2
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
                operator[2]._setPipes(_pipe0, null, true);
            case 6:  // OPX:con=7  
                // o0+o1(o0)+o2
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[1]._basePipe = _pipe0;
                operator[2]._setPipes(_pipe0, null, true);
            default:
                // o0+o1+o2
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
                operator[2]._setPipes(_pipe0, null, true);
        }
    }
    
    
    // alg operator=4
    private function _algorism4(alg : Int) : Void
    {
        _updateOperatorCount(4);
        _algorism = alg;
        switch (_algorism)
        {
            case 0:  // OPL3:con=0, MA3:con=4, OPX:con=0, 1(fbc=1)  
                // o3(o2(o1(o0)))
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0);
                operator[2]._setPipes(_pipe0, _pipe0);
                operator[3]._setPipes(_pipe0, _pipe0, true);
            case 1:  // OPX:con=2  
                // o3(o2(o0+o1))
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0);
                operator[2]._setPipes(_pipe0, _pipe0);
                operator[3]._setPipes(_pipe0, _pipe0, true);
            case 2:  // MA3:con=3, OPX:con=3  
                // o3(o0+o2(o1))
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe1);
                operator[2]._setPipes(_pipe0, _pipe1);
                operator[3]._setPipes(_pipe0, _pipe0, true);
            case 3:  // OPX:con=4, 5(fbc=1)  
                // o3(o1(o0)+o2)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0);
                operator[2]._setPipes(_pipe0);
                operator[3]._setPipes(_pipe0, _pipe0, true);
            case 4:  // OPL3:con=1, MA3:con=5, OPX:con=6, 7(fbc=1)  
                // o1(o0)+o3(o2)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[2]._setPipes(_pipe1);
                operator[3]._setPipes(_pipe0, _pipe1, true);
            case 5:  // OPX:con=12  
                // o1(o0)+o2(o0)+o3(o0)
                operator[0]._setPipes(_pipe1);
                operator[1]._setPipes(_pipe0, _pipe1, true);
                operator[2]._setPipes(_pipe0, _pipe1, true);
                operator[3]._setPipes(_pipe0, _pipe1, true);
            case 6:  // OPX:con=10, 11(fbc=1)  
                // o1(o0)+o2+o3
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[2]._setPipes(_pipe0, null, true);
                operator[3]._setPipes(_pipe0, null, true);
            case 7:  // MA3:con=2, OPX:con=15  
                // o0+o1+o2+o3
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
                operator[2]._setPipes(_pipe0, null, true);
                operator[3]._setPipes(_pipe0, null, true);
            case 8:  // OPL3:con=2, MA3:con=6, OPX:con=8  
                // o0+o3(o2(o1))
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe1);
                operator[2]._setPipes(_pipe1, _pipe1);
                operator[3]._setPipes(_pipe0, _pipe1, true);
            case 9:  // OPL3:con=3, MA3:con=7, OPX:con=13  
                // o0+o2(o1)+o3
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe1);
                operator[2]._setPipes(_pipe0, _pipe1, true);
                operator[3]._setPipes(_pipe0, null, true);
            case 10:  // for DX7 emulation  
                // o3(o0+o1+o2)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0);
                operator[2]._setPipes(_pipe0);
                operator[3]._setPipes(_pipe0, _pipe0, true);
            case 11:  // OPX:con=9  
                // o0+o3(o1+o2)
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe1);
                operator[2]._setPipes(_pipe1);
                operator[3]._setPipes(_pipe0, _pipe1, true);
            case 12:  // OPX:con=14  
                // o0+o1(o0)+o3(o2)
                operator[0]._setPipes(_pipe0);
                operator[1]._setPipes(_pipe0, _pipe0, true);
                operator[1]._basePipe = _pipe0;
                operator[2]._setPipes(_pipe1);
                operator[3]._setPipes(_pipe0, _pipe1, true);
            default:
                // o0+o1+o2+o3
                operator[0]._setPipes(_pipe0, null, true);
                operator[1]._setPipes(_pipe0, null, true);
                operator[2]._setPipes(_pipe0, null, true);
                operator[3]._setPipes(_pipe0, null, true);
        }
    }
    
    
    // analog like operation
    private function _analog(alg : Int) : Void
    {
        _updateOperatorCount(2);
        operator[0]._setPipes(_pipe0, null, true);
        operator[1]._setPipes(_pipe0, null, true);
        
        _algorism = ((alg >= 0 && alg <= 3)) ? alg : 0;
        _funcProcessType = PROC_ANA + _algorism;
        _funcProcess = _funcProcessList[_lfo_on][_funcProcessType];
    }
    
    
    // SiOPMOperator factory
    //--------------------------------------------------
    // Free list for SiOPMOperator
    private static var _freeOperators : Array<SiOPMOperator> = new Array<SiOPMOperator>();
    
    
    /** @private [internal] Alloc operator instance WITHOUT initializing. Call from SiOPMChannelFM. */
    private function _allocFMOperator() : SiOPMOperator {
        var returnOp = _freeOperators.pop();
        if (returnOp == null) {
            returnOp = new SiOPMOperator(_chip);
        }
        return returnOp;
    }
    
    
    /** @private [internal] Free operator instance. Call from SiOPMChannelFM. */
    private function _freeFMOperator(osc : SiOPMOperator) : Void {
        _freeOperators.push(osc);
    }
}


