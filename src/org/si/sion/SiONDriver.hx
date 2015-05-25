//----------------------------------------------------------------------------------------------------
// SiON driver
//  Copyright (c) 2008 keim All rights reserved.
//  Distributed under BSD-style license (see org.si.license.txt).
//----------------------------------------------------------------------------------------------------


package org.si.sion;

import openfl.utils.Endian;
import openfl.utils.Timer;
import openfl.errors.*;
import openfl.events.*;
import openfl.media.*;
import openfl.net.*;
import openfl.display.Sprite;
import flash.Lib;

import openfl.utils.ByteArray;
import org.si.utils.SLLint;
import org.si.sion.events.*;
import org.si.sion.sequencer.base.MMLSequence;
import org.si.sion.sequencer.base.MMLEvent;
import org.si.sion.sequencer.SiMMLSequencer;
import org.si.sion.sequencer.SiMMLTrack;
import org.si.sion.sequencer.SiMMLEnvelopTable;
import org.si.sion.sequencer.SiMMLTable;
import org.si.sion.sequencer.SiMMLVoice;
import org.si.sion.module.ISiOPMWaveInterface;
import org.si.sion.module.SiOPMTable;
import org.si.sion.module.SiOPMModule;
import org.si.sion.module.SiOPMChannelParam;
import org.si.sion.module.SiOPMWaveTable;
import org.si.sion.module.SiOPMWavePCMTable;
import org.si.sion.module.SiOPMWavePCMData;
import org.si.sion.module.SiOPMWaveSamplerTable;
import org.si.sion.module.SiOPMWaveSamplerData;
import org.si.sion.effector.SiEffectModule;
import org.si.sion.utils.soundloader.SoundLoader;
import org.si.sion.utils.SiONUtil;
import org.si.sion.utils.Fader;
import org.si.sion.SiONData;

#if MIDI_ENABLED
import org.si.sion.midi.MIDIModule;
import org.si.sion.midi.SiONMIDIEventFlag;
import org.si.sion.midi.SMFData;
import org.si.sion.midi.SiONDataConverterSMF;
#end

// Dispatching events
/** @eventType org.si.sion.events.SiONEvent.QUEUE_PROGRESS */
@:meta(Event(name="queueProgress",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.QUEUE_COMPLETE */
@:meta(Event(name="queueComplete",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.QUEUE_CANCEL */
@:meta(Event(name="queueCancel",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.STREAM */
@:meta(Event(name="stream",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.STREAM_START */
@:meta(Event(name="streamStart",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.STREAM_STOP */
@:meta(Event(name="streamStop",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.FINISH_SEQUENCE */
@:meta(Event(name="finishSequence",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.FADE_PROGRESS */
@:meta(Event(name="fadeProgress",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.FADE_IN_COMPLETE */
@:meta(Event(name="fadeInComplete",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONEvent.FADE_OUT_COMPLETE */
@:meta(Event(name="fadeOutComplete",type="org.si.sion.events.SiONEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.NOTE_ON_STREAM */
@:meta(Event(name="noteOnStream",type="org.si.sion.events.SiONTrackEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.NOTE_OFF_STREAM */
@:meta(Event(name="noteOffStream",type="org.si.sion.events.SiONTrackEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.NOTE_ON_FRAME */
@:meta(Event(name="noteOnFrame",type="org.si.sion.events.SiONTrackEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.NOTE_OFF_FRAME */
@:meta(Event(name="noteOffFrame",type="org.si.sion.events.SiONTrackEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.BEAT */
@:meta(Event(name="beat",type="org.si.sion.events.SiONTrackEvent"))

/** @eventType org.si.sion.events.SiONTrackEvent.CHANGE_BPM */
@:meta(Event(name="changeBPM",type="org.si.sion.events.SiONTrackEvent"))



/** SiONDriver class provides the driver of SiON's digital signal processor emulator. SiON's all basic operations are provided as SiONDriver's properties, methods and events. You can create only one SiONDriver instance in one SWF file, and the error appears when you try to create plural SiONDrivers.<br/>
 * @see SiONData
 * @see SiONVoice
 * @see org.si.sion.events.SiONEvent
 * @see org.si.sion.events.SiONTrackEvent
 * @see org.si.sion.module.SiOPMModule
 * @see org.si.sion.sequencer.SiMMLSequencer
 * @see org.si.sion.effector.SiEffectModule
@example 1) The simplest sample. Create new instance and call play with MML string.<br/>
<listing version="3.0">
// create driver instance.
var driver:SiONDriver = new SiONDriver();
// call play() with mml string whenever you want to play sound.
driver.play("t100 l8 [ ccggaag4 ffeeddc4 | [ggffeed4]2 ]2");
</listing>
 */

class SiONDriver extends Sprite implements ISiOPMWaveInterface
{
    public static var mutex(get, never) : SiONDriver;
    public var mmlString(get, never) : String;
    public var data(get, never) : SiONData;
    public var sound(get, never) : Sound;
    public var soundChannel(get, never) : SoundChannel;
    public var fader(get, never) : Fader;
    public var trackCount(get, never) : Int;
    public var bufferLength(get, never) : Int;
    public var sampleRate(get, never) : Float;
    public var bitRate(get, never) : Float;
    public var volume(get, set) : Float;
    public var pan(get, set) : Float;
    public var compileTime(get, never) : Int;
    public var renderTime(get, never) : Int;
    public var processTime(get, never) : Int;
    public var jobProgress(get, never) : Float;
    public var jobQueueProgress(get, never) : Float;
    public var latency(get, never) : Float;
    public var jobQueueLength(get, never) : Int;
    public var isJobExecuting(get, never) : Bool;
    public var isPlaying(get, never) : Bool;
    public var isPaused(get, never) : Bool;
    public var backgroundSound(get, never) : Sound;
    public var backgroundSoundTrack(get, never) : SiMMLTrack;
    public var backgroundSoundFadeOutTime(get, never) : Float;
    public var backgroundSoundFadeInTime(get, never) : Float;
    public var backgroundSoundFadeGapTime(get, never) : Float;
    public var backgroundSoundVolume(get, set) : Float;
#if MIDI_ENABLED
    public var midiModule(get, never) : MIDIModule;
#end
    public var position(get, set) : Float;
    public var maxTrackCount(get, set) : Int;
    public var bpm(get, set) : Float;
    public var autoStop(get, set) : Bool;
    public var pauseWhileLoading(get, set) : Bool;
    public var debugMode(get, set) : Bool;
    public var noteOnExceptionMode(get, set) : Int;
    public var dispatchChangeBPMEventWhenPositionChanged(get, set) : Bool;
    public static var allowPluralDrivers(get, set) : Bool;

    // constants
    //----------------------------------------
    /** version number */
    public static inline var VERSION : String = "0.6.6.0";
    
    
    /** note-on exception mode "ignore", SiON does not consider about track ID's conflict in noteOn() method (default). */
    public static inline var NEM_IGNORE : Int = 0;
    /** note-on exception mode "reject", Reject new note when the track IDs are conflicted. */
    public static inline var NEM_REJECT : Int = 1;
    /** note-on exception mode "overwrite", Overwrite current note when the track IDs are conflicted. */
    public static inline var NEM_OVERWRITE : Int = 2;
    /** note-on exception mode "shift", Shift the sound timing to next quantize when the track IDs are conflicted. */
    public static inline var NEM_SHIFT : Int = 3;
    
    private static inline var NEM_MAX : Int = 4;
    
    
    // event listener type
    private static inline var NO_LISTEN : Int = 0;
    private static inline var LISTEN_QUEUE : Int = 1;
    private static inline var LISTEN_PROCESS : Int = 2;
    
    // time avaraging sample count
    private static inline var TIME_AVARAGING_COUNT : Int = 8;
    
    
    
    
    // variables
    //----------------------------------------
    /** SiOPM digital signal processor module instance.  */
    public var module : SiOPMModule;
    
    /** Effector module instance. */
    public var effector : SiEffectModule;
    
    /** Sequencer module instance. */
    public var sequencer : SiMMLSequencer;
    
    
    // private:
    //----- general
    private var _data : SiONData;  // data to compile or process  
    private var _tempData : SiONData;  // temporary data  
    private var _mmlString : String;  // mml string of previous compiling  
    //----- sound related
    private var _sound : Sound;  // sound stream instance  
    private var _soundChannel : SoundChannel;  // sound channel instance  
    private var _soundTransform : SoundTransform;  // sound transform  
    private var _fader : Fader;  // sound fader  
    //----- SiOPM DSP module related
    private var _channelCount : Int;  // module output channels (1 or 2)  
    private var _sampleRate : Int;  // module output frequency ratio (44100 or 22050)
    private var _bitRate : Int;  // module output bitrate  
    private var _bufferLength : Int;  // module and streaming buffer size (8192, 4096 or 2048)  
    private var _debugMode : Bool;  // true; throw Error, false; throw ErrorEvent  
    private var _dispatchStreamEvent : Bool;  // dispatch steam event  
    private var _dispatchFadingEvent : Bool;  // dispatch fading event  
    private var _inStreaming : Bool;  // in streaming  
    private var _preserveStop : Bool;  // preserve stop after streaming  
    private var _suspendStreaming : Bool;  // suspend streaming  
    private var _suspendWhileLoading : Bool;  // suspend starting steam while loading  
    private var _loadingSoundList : Array<Dynamic>;  // loading sound list  
    private var _isFinishSeqDispatched : Bool;  // FINISH_SEQUENCE event already dispacthed  
    //----- operation related
    private var _autoStop : Bool;  // auto stop when the sequence finished  
    private var _noteOnExceptionMode : Int;  // track id exception mode  
    private var _isPaused : Bool;  // flag to pause  
    private var _position : Float;  // start position [ms]  
    private var _masterVolume : Float;  // master volume  
    private var _faderVolume : Float;  // fader volume  
    private var _dispatchChangeBPMEventWhenPositionChanged : Bool;
    //----- background sound
    private var _backgroundSound : Sound;  // background Sound  
    private var _backgroundLoopPoint : Float;  // loop point (in seconds)  
    private var _backgroundFadeOutFrames : Int;  // fading out frames  
    private var _backgroundFadeInFrames : Int;  // fading in frames  
    private var _backgroundFadeGapFrames : Int;  // fading gap frames  
    private var _backgroundTotalFadeFrames : Int;  // total fading in frames  
    private var _backgroundVoice : SiONVoice;  // voice  
    private var _backgroundSample : SiOPMWaveSamplerData;  // sampling data  
    private var _backgroundTrack : SiMMLTrack;  // track for background Sound  
    private var _backgroundTrackFadeOut : SiMMLTrack;  // track for background Sound's cross fading  
    //----- queue
    private var _queueInterval : Int;  // interupting interval to execute queued jobs  
    private var _queueLength : Int;  // queue length to execute  
    private var _jobProgress : Float;  // progression of current job  
    private var _currentJob : Int;  // current job 0=no job, 1=compile, 2=render  
    private var _jobQueue : Array<SiONDriverJob> = null;  // compiling/rendering jobs queue  
    private var _trackEventQueue : Array<SiONTrackEvent>;  // SiONTrackEvents queue  
    //----- timer interruption
    private var _timerSequence : MMLSequence;  // global sequence  
    private var _timerIntervalEvent : MMLEvent;  // MMLEvent.GLOBAL_WAIT event  
    private var _timerCallback : Void->Void;  // callback function
    //----- rendering
    private var _renderBuffer : Array<Float>;  // rendering buffer  
    private var _renderBufferChannelCount : Int;  // rendering buffer channel count  
    private var _renderBufferIndex : Int;  // rendering buffer writing index  
    private var _renderBufferSizeMax : Int;  // maximum value of rendering buffer size  
    //----- timers
    private var _timeCompile : Int;  // previous compiling time.  
    private var _timeRender : Int;  // previous rendering time.  
    private var _timeProcess : Int;  // averge processing time in 1sec.  
    private var _timeProcessTotal : Int;  // total processing time in last 8 bufferings.  
    private var _timeProcessData : SLLint;  // processing time data of last 8 bufferings.  
    private var _timeProcessAveRatio : Float;  // number to averaging _timeProcessTotal  
    private var _timePrevStream : Int;  // previous streaming time.  
    private var _latency : Float;  // streaming latency [ms]  
    private var _prevFrameTime : Int;  // previous frame time  
    private var _frameRate : Int;  // frame rate  
    //----- listeners management
    private var _eventListenerPrior : Int;  // event listeners priority  
    private var _listenEvent : Int;  // current lintening event  
#if MIDI_ENABLED
    //----- MIDI related
    private var _midiModule : MIDIModule;  // midi sound module  
    private var _midiConverter : SiONDataConverterSMF;  // SMF data converter  
#end
    
    // mutex instance
    private static var _mutex : SiONDriver = null;  // unique instance  
    private static var _allowPluralDrivers : Bool = false;  // allow plural drivers  
    
    
    
    // properties
    //----------------------------------------
    /** Instance of unique SiONDriver. null when new SiONDriver is not created yet. */
    private static function get_mutex() : SiONDriver{
        return _mutex;
    }
    
    
    //----- data
    /** MML string (this property is only available during compiling). */
    private function get_mmlString() : String{
        return _mmlString;
    }
    
    /** Data to compile, render and process. */
    private function get_data() : SiONData{
        return _data;
    }
    
    /** flash.media.Sound instance to stream SiON's sound. */
    private function get_sound() : Sound{
        return _sound;
    }
    
    /** flash.media.SoundChannel instance of SiON's sound stream (this property is only available during streaming). */
    private function get_soundChannel() : SoundChannel{
        return _soundChannel;
    }
    
    /** Fader to control fade-in/out. You can check activity by "fader.isActive". */
    private function get_fader() : Fader{
        return _fader;
    }
    
    
    //----- sound paramteters
    /** The number of sound tracks (this property is only available during streaming). */
    private function get_trackCount() : Int{
        return sequencer.tracks.length;
    }
    
    /** Streaming buffer length. */
    private function get_bufferLength() : Int{
        return _bufferLength;
    }
    /** Sample rate (44100 is only available in current version). */
    private function get_sampleRate() : Float{
        return _sampleRate;
    }
    /** bit rate, the value of 0 means the wave is represented as float value[-1 - +1]. */
    private function get_bitRate() : Float{
        return _bitRate;
    }
    
    /** Sound volume. */
    private function get_volume() : Float{
        return _masterVolume;
    }
    private function set_volume(v : Float) : Float{
        _masterVolume = v;
        _soundTransform.volume = _masterVolume * _faderVolume;
        if (_soundChannel != null)             _soundChannel.soundTransform = _soundTransform;
        return v;
    }
    
    /** Sound panning. */
    private function get_pan() : Float{
        return _soundTransform.pan;
    }
    private function set_pan(p : Float) : Float{
        _soundTransform.pan = p;
        if (_soundChannel != null)             _soundChannel.soundTransform = _soundTransform;
        return p;
    }
    
    
    //----- measured times
    /** previous compiling time [ms]. */
    private function get_compileTime() : Int{
        return _timeCompile;
    }
    
    /** previous rendering time [ms]. */
    private function get_renderTime() : Int{
        return _timeRender;
    }
    
    /** average processing time in 1sec [ms]. */
    private function get_processTime() : Int{
        return _timeProcess;
    }
    
    /** progression of current compiling/rendering (0=start -> 1=finish). */
    private function get_jobProgress() : Float{
        return _jobProgress;
    }
    
    /** progression of all queued jobs (0=start -> 1=finish). */
    private function get_jobQueueProgress() : Float{
        if (_queueLength == 0)             return 1;
        return (_queueLength - _jobQueue.length - 1 + _jobProgress) / _queueLength;
    }
    
    /** streaming latency [ms]. */
    private function get_latency() : Float{
        return _latency;
    }
    
    /** compiling/rendering jobs queue length. */
    private function get_jobQueueLength() : Int{
        return _jobQueue.length;
    }
    
    
    //----- status flags
    /** Is job executing ? */
    private function get_isJobExecuting() : Bool{
        return (_jobProgress > 0 && _jobProgress < 1);
    }
    
    /** Is streaming ? */
    private function get_isPlaying() : Bool{
        return (_soundChannel != null);
    }
    
    /** Is paused ? */
    private function get_isPaused() : Bool{
        return _isPaused;
    }
    
    
    //----- background sound
    /** background sound */
    private function get_backgroundSound() : Sound{
        return _backgroundSound;
    }
    
    /** track for background sound */
    private function get_backgroundSoundTrack() : SiMMLTrack{
        return _backgroundTrack;
    }
    
    /** background sound fading out time in seconds */
    private function get_backgroundSoundFadeOutTime() : Float{
        return _backgroundFadeOutFrames * _bufferLength / _sampleRate;
    }
    
    /** background sound fading in time in seconds */
    private function get_backgroundSoundFadeInTime() : Float{
        return _backgroundFadeInFrames * _bufferLength / _sampleRate;
    }
    
    /** background sound fading time in seconds */
    private function get_backgroundSoundFadeGapTime() : Float{
        return _backgroundFadeGapFrames * _bufferLength / _sampleRate;
    }
    
    /** background sound volume @default 0.5 */
    private function get_backgroundSoundVolume() : Float{
        return _backgroundVoice.channelParam.volumes[0];
    }
    private function set_backgroundSoundVolume(vol : Float) : Float{
        _backgroundVoice.channelParam.volumes[0] = vol;
        if (_backgroundTrack != null) _backgroundTrack.masterVolume = Math.round(vol * 128);
        if (_backgroundTrackFadeOut != null) _backgroundTrackFadeOut.masterVolume = Math.round(vol * 128);
        return vol;
    }

#if MIDI_ENABLED
    /** MIDI sound module */
    private function get_midiModule() : MIDIModule{
        return _midiModule;
    }
#end
    
    //----- operation
    /** Get playing position[ms] of current data, or Set initial position of playing data. @default 0 */
    private function get_position() : Float{
        return sequencer.processedSampleCount * 1000 / _sampleRate;
    }
    private function set_position(pos : Float) : Float{
        _position = pos;
        if (sequencer.isReadyToProcess) {
            sequencer._resetAllTracks();
            sequencer.dummyProcess(Math.round(_position * _sampleRate * 0.001));
        }
        return pos;
    }
    
    
    //----- other parameters
    /** The maximum limit of sound tracks. @default 128 */
    private function get_maxTrackCount() : Int{
        return sequencer._maxTrackCount;
    }
    private function set_maxTrackCount(max : Int) : Int{
        sequencer._maxTrackCount = max;
        return max;
    }
    
    /** Beat par minute value of SiON's play. @default 120 */
    private function get_bpm() : Float{
        return ((sequencer.isReadyToProcess)) ? sequencer.bpm : sequencer.setting.defaultBPM;
    }
    private function set_bpm(t : Float) : Float{
        sequencer.setting.defaultBPM = t;
        if (sequencer.isReadyToProcess) {
            if (!sequencer.isEnableChangeBPM)                 throw errorCannotChangeBPM();
            sequencer.bpm = t;
        }
        return t;
    }
    
    /** Auto stop when the sequence finished or fade-outed. @default false */
    private function get_autoStop() : Bool{
        return _autoStop;
    }
    private function set_autoStop(mode : Bool) : Bool{
        _autoStop = mode;
        return mode;
    }
    
    /** pause while loading sound @default true */
    private function get_pauseWhileLoading() : Bool{
        return _suspendWhileLoading;
    }
    private function set_pauseWhileLoading(b : Bool) : Bool{
        _suspendWhileLoading = b;
        return b;
    }
    
    /** Debug mode, true; throw Error / false; throw ErrorEvent when error appears inside. @default false */
    private function get_debugMode() : Bool{
        return _debugMode;
    }
    private function set_debugMode(mode : Bool) : Bool{
        _debugMode = mode;
        return mode;
    }
    
    /** Note on exception mode, this mode is refered when the noteOn() sound's track IDs are conflicted at the same moment. This value have to be SiONDriver.NEM_*. @default NEM_IGNORE. 
     *  @see #NEM_IGNORE
     *  @see #NEM_REJECT
     *  @see #NEM_OVERWRITE
     *  @see #NEM_SHIFT
     */
    private function get_noteOnExceptionMode() : Int{
        return _noteOnExceptionMode;
    }
    private function set_noteOnExceptionMode(mode : Int) : Int{
        _noteOnExceptionMode = ((0 < mode && mode < NEM_MAX)) ? mode : 0;
        return mode;
    }
    
    /** dispatch CHANGE_BPM Event When position changed @default true */
    private function get_dispatchChangeBPMEventWhenPositionChanged() : Bool{
        return _dispatchChangeBPMEventWhenPositionChanged;
    }
    private function set_dispatchChangeBPMEventWhenPositionChanged(b : Bool) : Bool{
        _dispatchChangeBPMEventWhenPositionChanged = b;
        return b;
    }
    
    /** Allow plural drivers <b>[CAUTION] This function is quite experimental</b> and plural drivers require large memory area. */
    private static function set_allowPluralDrivers(b : Bool) : Bool{
        _allowPluralDrivers = b;
        return b;
    }
    private static function get_allowPluralDrivers() : Bool{
        return _allowPluralDrivers;
    }
    
    
    
    
    // constructor
    //----------------------------------------
    /** Create driver to manage the synthesizer, sequencer and effector. Only one SiONDriver instance can be created.
     *  @param bufferLength Buffer size of sound stream. The value of 8192, 4096 or 2048 is available.
     *  @param channel Channel count. 1(monoral) or 2(stereo) is available.
     *  @param sampleRate Sampling ratio of wave. 44100 is only available in current version.
     *  @param bitRate Bit ratio of wave. 0 means float value [-1 to 1].
     */
    public function new(bufferLength : Int = 2048, channelCount : Int = 2, sampleRate : Int = 44100, bitRate : Int = 0)
    {
        super();

        // check mutex
        if (_mutex != null && !_allowPluralDrivers) throw errorPluralDrivers();

        // check parameters
        if (bufferLength != 2048 && bufferLength != 4096 && bufferLength != 8192) throw errorParamNotAvailable("stream buffer", bufferLength);
        if (channelCount != 1 && channelCount != 2) throw errorParamNotAvailable("channel count", channelCount);
        if (sampleRate != 44100) throw errorParamNotAvailable("sampling rate", sampleRate);

        // initialize tables
        var dummy : Dynamic;
        dummy = SiOPMTable.instance;  //initialize(3580000, 1789772.5, 44100) sampleRate;  
        dummy = SiMMLTable.instance;  //initialize();  

        // allocation
        _jobQueue = new Array<SiONDriverJob>();
        module = new SiOPMModule();
        effector = new SiEffectModule(module);
        sequencer = new SiMMLSequencer(module, _callbackEventTriggerOn, _callbackEventTriggerOff, _callbackTempoChanged);
        _sound = new Sound();
        _soundTransform = new SoundTransform();
        _fader = new Fader();
        _timerSequence = new MMLSequence();
        _loadingSoundList = [];
#if MIDI_ENABLED
        _midiModule = new MIDIModule();
        _midiConverter = new SiONDataConverterSMF(null, _midiModule);
#end

        // initialize
        _tempData = null;
        _channelCount = channelCount;
        _sampleRate = sampleRate;  // sampleRate; 44100 is only in current version.  
        _bitRate = bitRate;
        _bufferLength = bufferLength;
        _listenEvent = NO_LISTEN;
        _dispatchStreamEvent = false;
        _dispatchFadingEvent = false;
        _preserveStop = false;
        _inStreaming = false;
        _suspendStreaming = false;
        _suspendWhileLoading = true;
        _autoStop = false;
        _noteOnExceptionMode = NEM_IGNORE;
        _debugMode = false;
        _isFinishSeqDispatched = false;
        _dispatchChangeBPMEventWhenPositionChanged = true;
        _timerCallback = null;
        _timerSequence.initialize();
        _timerSequence.appendNewEvent(MMLEvent.REPEAT_ALL, 0);
        _timerSequence.appendNewEvent(MMLEvent.TIMER, 0);
        _timerIntervalEvent = _timerSequence.appendNewEvent(MMLEvent.GLOBAL_WAIT, 0, 0);

        _backgroundSound = null;
        _backgroundLoopPoint = -1;
        _backgroundFadeInFrames = 0;
        _backgroundFadeOutFrames = 0;
        _backgroundFadeGapFrames = 0;
        _backgroundTotalFadeFrames = 0;
        _backgroundVoice = new SiONVoice(SiMMLTable.MT_SAMPLE);
        _backgroundVoice.updateVolumes = true;
        _backgroundSample = null;
        _backgroundTrack = null;
        _backgroundTrackFadeOut = null;
        
        _position = 0;
        _masterVolume = 1;
        _faderVolume = 1;
        _soundTransform.pan = 0;
        _soundTransform.volume = _masterVolume * _faderVolume;
        
        _eventListenerPrior = 1;
        _trackEventQueue = new Array<SiONTrackEvent>();
        
        _queueInterval = 500;
        _jobProgress = 0;
        _currentJob = 0;
        _queueLength = 0;
        
        _timeCompile = 0;
        _timeProcessTotal = 0;
        _timeProcessData = SLLint.allocRing(TIME_AVARAGING_COUNT);
        _timeProcessAveRatio = _sampleRate / (_bufferLength * TIME_AVARAGING_COUNT);
        _timePrevStream = 0;
        _latency = 0;
        _prevFrameTime = 0;
        _frameRate = 1;
        
        _mmlString = null;
        _data = null;
        _soundChannel = null;

        // register sound streaming function
        _sound.addEventListener("sampleData", _streaming);
        
        // set mutex
        _mutex = this;
    }
    
    
    
    
    // interfaces for data preparation
    //----------------------------------------
    /** Compile MML string to SiONData. 
     *  @param mml MML string to compile.
     *  @param data SiONData to compile. The SiONDriver creates new SiONData instance when this argument is null.
     *  @return Compiled data.
     */
    public function compile(mml : String, data : SiONData = null) : SiONData
    {
        trace('SDR.compile()');
        try{
            // stop sound
            stop();

            // compile immediately
            var t : Int = Math.round(haxe.Timer.stamp() * 1000);
            _prepareCompile(mml, data);
            _jobProgress = sequencer.compile(0);
            _timeCompile = Math.round(haxe.Timer.stamp() * 1000) - t;
            _mmlString = null;
        }
        catch (e : Error){
            // error
            if (_debugMode) throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }
        
        return _data;
    }
    
    
    /** Push queue job to compile MML string. Start compiling after calling startQueue.<br/>
     *  @param mml MML string to compile.
     *  @param data SiONData to compile.
     *  @return Queue length.
     *  @see #startQueue()
     */
    public function compileQueue(mml : String, data : SiONData) : Int
    {
        if (mml == null || data == null)             return _jobQueue.length;
        return _jobQueue.push(new SiONDriverJob(mml, null, data, 2, false));
    }
    
    
    
    
    // interfaces for sound rendering
    //----------------------------------------
    /** Render wave data from MML string or SiONData. This method may take long time, please consider the using renderQueue() instead.
     *  @param data SiONData or mml String to play.
     *  @param renderBuffer Rendering target. null to create new buffer. The length of this argument limits the rendering length (except for 0).
     *  @param renderBufferChannelCount Channel count of renderBuffer. 2 for stereo and 1 for monoral.
     *  @param resetEffector reset all effectors before play data.
     *  @return rendered wave data as Vector.&lt;Number&gt;.
     */
    public function render(data : Dynamic, renderBuffer : Array<Float> = null, renderBufferChannelCount : Int = 2, resetEffector : Bool = true) : Array<Float>
    {
        try {
            // stop sound
            stop();
            
            // rendering immediately
            var t : Int = Math.round(haxe.Timer.stamp() * 1000);
            _prepareRender(data, renderBuffer, renderBufferChannelCount, resetEffector);
            while (true) {
                if (_rendering()) break;
            }
            _timeRender = Math.round(haxe.Timer.stamp() * 1000) - t;
        }
        catch (e : Error) {
            trace('Error while rendering: $e');
            // error
            _removeAllEventListners();
            if (_debugMode) throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }
        
        return _renderBuffer;
    }
    
    
    /** Push queue job to render sound. Start rendering after calling startQueue.<br/>
     *  @param data SiONData or mml String to render.
     *  @param renderBuffer Rendering target. The length of renderBuffer limits rendering length except for 0.
     *  @param renderBufferChannelCount Channel count of renderBuffer. 2 for stereo and 1 for monoral.
     *  @return Queue length.
     *  @see #startQueue()
     */
    public function renderQueue(data : Dynamic, renderBuffer : Array<Float>, renderBufferChannelCount : Int = 2, resetEffector : Bool = false) : Int
    {
        if (data == null || renderBuffer == null)             return _jobQueue.length;
        
        if (Std.is(data, String)) {
            var compiled : SiONData = new SiONData();
            var dataString : String;
            try {
                dataString = cast(data, String);
            }
            catch (e:Dynamic) {
                dataString = null;
            }
            _jobQueue.push(new SiONDriverJob(dataString, null, compiled, 2, false));
            return _jobQueue.push(new SiONDriverJob(null, renderBuffer, compiled, renderBufferChannelCount, resetEffector));
        }
        else 
        if (Std.is(data, SiONData)) {
            var sionData : SiONData;
            try {
                sionData = cast(data, SiONData);
            }
            catch (e:Dynamic) {
                sionData = null;
            }
            return _jobQueue.push(new SiONDriverJob(null, renderBuffer, sionData, renderBufferChannelCount, resetEffector));
        }
        
        var e : Error = errorDataIncorrect();
        if (_debugMode) throw e
        else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        return _jobQueue.length;
    }
    
    
    
    
    // interfaces for jobs queue
    //----------------------------------------
    /** Execute all elements queued by compileQueue() and renderQueue().
     *  After calling this function, the SiONEvent.QUEUE_PROGRESS, SiONEvent.QUEUE_COMPLETE and ErrorEvent.ERROR events will be dispatched.<br/>
     *  The SiONEvent.QUEUE_PROGRESS is dispatched when it's executing queued job.<br/>
     *  The SiONEvent.QUEUE_COMPLETE is dispatched when finish all queued jobs.<br/>
     *  The ErrorEvent.ERROR is dispatched when some error appears during the compile.<br/>
     *  @param interval Interupting interval
     *  @return Queue length.
     *  @see #compileQueue()
     *  @see #renderQueue()
     */
    public function startQueue(interval : Int = 500) : Int
    {
        try{
            stop();
            _queueLength = _jobQueue.length;
            if (_jobQueue.length > 0) {
                _queueInterval = interval;
                _executeNextJob();
                _queue_addAllEventListners();
            }
        }
        catch (e : Error) {
            trace('Error in startQueue: $e');
            // error
            _removeAllEventListners();
            _cancelAllJobs();
            if (_debugMode)                 throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }
        return _queueLength;
    }
    
    
    /** Listen loading status of flash.media.Sound instance. 
     *  When SiONDriver.pauseWhileLoading is true, SiONDriver starts streaming after all Sound instances passed by this function are loaded.
     *  @param sound Sound or SoundLoader instance to listern 
     *  @param prior listening priority 
     *  @return return false when the sound is loaded already.
     *  @see #pauseWhileLoading()
     *  @see #clearLoadingSoundList()
     */
    public function listenSoundLoadingStatus(sound : Dynamic, prior : Int = -99999) : Bool
    {
        if (Lambda.indexOf(_loadingSoundList, sound) != -1)             return true;
        if (Std.is(sound, Sound)) {
            if (sound.bytesTotal == 0 || sound.bytesLoaded != sound.bytesTotal) {
                _loadingSoundList.push(sound);
                sound.addEventListener(Event.COMPLETE, _onSoundEvent, false, prior);
                sound.addEventListener(IOErrorEvent.IO_ERROR, _onSoundEvent, false, prior);
                return true;
            }
        }
        else 
        if (Std.is(sound, SoundLoader)) {
            if (sound.loadingFileCount > 0) {
                _loadingSoundList.push(sound);
                sound.addEventListener(Event.COMPLETE, _onSoundEvent, false, prior);
                sound.addEventListener(ErrorEvent.ERROR, _onSoundEvent, false, prior);
                return true;
            }
        }
        else {
            throw errorCannotListenLoading();
        }
        return false;
    }
    
    
    /** Clear all listening sound list registerd by SiONDriver.listenLoadingStatus().
     */
    public function clearSoundLoadingList() : Void
    {
        _loadingSoundList.splice(0,_loadingSoundList.length);
    }
    
    
    /** Set hash table of Sound instance refered from #SAMPLER and #PCMWAVE commands. You have to set this table BEFORE compile mml.
     */
    public function setSoundReferenceTable(soundReferenceTable : Map<String, Dynamic> = null) : Void
    {
        SiOPMTable.instance.soundReference = soundReferenceTable;
        if (SiOPMTable.instance.soundReference == null) {
            SiOPMTable.instance.soundReference = new Map<String, Dynamic>();
        }
    }
    
    
    
    // interfaces for sound streaming
    //----------------------------------------
    /** Play SiONData or MML string.
     *  @param data SiONData, mml String, Sound object, mp3 file URLRequest or SMFData object to play. You can pass null when resume after pause or streaming without any data.
     *  @param resetEffector reset all effectors before play data.
     *  @return SoundChannel instance to play data. This instance is same as soundChannel property.
     *  @see #soundChannel
     */
    public function play(data : Dynamic = null, resetEffector : Bool = true) : SoundChannel
    {
        try{
            if (_isPaused) {
                _isPaused = false;
            }
            else {
                // stop sound
                stop();

                // preparation
                _prepareProcess(data, resetEffector);

                // initialize
                _timeProcessTotal = 0;
                for (i in 0...TIME_AVARAGING_COUNT){
                    _timeProcessData.i = 0;
                    _timeProcessData = _timeProcessData.next;
                }
                _isPaused = false;
                _isFinishSeqDispatched = (data == null);
                
                // start streaming
                _suspendStreaming = true;
                _soundChannel = _sound.play();
                _soundChannel.soundTransform = _soundTransform;
                _process_addAllEventListners();
            }
        }
        catch (e : Error) {
            // error
            if (_debugMode) throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }
        
        return _soundChannel;
    }
    
    
    /** Stop sound. */
    public function stop() : Void
    {
        if (_soundChannel != null) {
            if (_inStreaming) {
                _preserveStop = true;
            }
            else {
                stopBackgroundSound();
                _removeAllEventListners();
                _preserveStop = false;
                _soundChannel.stop();
                _soundChannel = null;
                _latency = 0;
                _fader.stop();
                _faderVolume = 1;
                _isPaused = false;
                _soundTransform.volume = _masterVolume;
                sequencer._stopSequence();
                
                // dispatch streaming stop event
                dispatchEvent(new SiONEvent(SiONEvent.STREAM_STOP, this));
            }
        }
    }
    
    
    /** Reset signal processor. The effector and sequencer will not be reset. If you want to reset all, call SiONDriver.stop() instead. */
    public function reset() : Void
    {
        sequencer._resetAllTracks();
    }
    
    
    /** Pause sound. You can resume it by resume() or play(). @see resume() @see play() */
    public function pause() : Void
    {
        _isPaused = true;
    }
    
    
    /** Resume sound. same as play() after pause(). @see pause() */
    public function resume() : Void
    {
        _isPaused = false;
    }
    
    
    /** Play Sound as a background.
     *  @param sound Sound instance to play background.
     *  @param mixLevel Mixing level (0-1), this value same as backgroundSoundVolume.
     *  @param loopPoint loop point in second. -1 sets no loop
     *  @see backgroundSound 
     */
    public function setBackgroundSound(sound : Sound, mixLevel : Float = 0.5, loopPoint : Float = -1) : Void
    {
        backgroundSoundVolume = mixLevel;
        _backgroundLoopPoint = loopPoint;
        _setBackgroundSound(sound);
    }
    
    
    /** Stop background sound. */
    public function stopBackgroundSound() : Void
    {
        _setBackgroundSound(null);
    }
    
    
    /** set fading time of background sound
     *  @param fadeInTime  fade in time [sec]. positive value only
     *  @param fadeOutTime fade out time [sec]. positive value only
     *  @param gapTime     gap between 2 sound [sec]. You can specify negative values to play with cross fading.
     */
    public function setBackgroundSoundFadeTime(fadeInTime : Float, fadeOutTime : Float, gapTime : Float) : Void
    {
        var t2f : Float = _sampleRate / _bufferLength;
        _backgroundFadeInFrames = Math.floor(fadeInTime * t2f);
        _backgroundFadeOutFrames = Math.floor(fadeOutTime * t2f);
        _backgroundFadeGapFrames = Math.floor(gapTime * t2f);
        _backgroundTotalFadeFrames = _backgroundFadeOutFrames + _backgroundFadeInFrames + _backgroundFadeGapFrames;
    }
    
    
    /** Fade in all sound played by SiONDriver. You can set this method before calling play().
     *  @param time Fading time [second].
     */
    public function fadeIn(time : Float) : Void
    {
        _fader.setFade(_fadeVolume, 0, 1, Math.floor(time * _sampleRate / _bufferLength));
        _dispatchFadingEvent = (Lib.current.hasEventListener(SiONEvent.FADE_PROGRESS));
    }
    
    
    /** Fade out all sound played by SiONDriver.
     *  @param time Fading time [second].
     */
    public function fadeOut(time : Float) : Void
    {
        _fader.setFade(_fadeVolume, 1, 0, Std.int(time * _sampleRate / _bufferLength));
        _dispatchFadingEvent = (Lib.current.hasEventListener(SiONEvent.FADE_PROGRESS));
    }
    
    
    /** Set timer interruption.
     *  @param length16th Interupting interval in 16th beat.
     *  @param callback Callback function. the Type is function():void.
     */
    public function setTimerInterruption(length16th : Float = 1, callback : Void->Void = null) : Void
    {
        _timerIntervalEvent.length = Math.floor(length16th * sequencer.setting.resolution * 0.0625);
        trace('***** setTimerInterruption: $length16th length: ${_timerIntervalEvent.length}');
        _timerCallback = (length16th > 0) ? callback : null;
    }
    
    
    /** Set callback interval of SiONTrackEvent.BEAT.
     *  @param length16th Interval in 16th beat. 2^n is only available(1,2,4,8,16....).
     */
    public function setBeatCallbackInterval(length16th : Float = 1) : Void
    {
        var filter : Int = 1;
        while (length16th > 1.5) {
            filter <<= 1;
            length16th *= 0.5;
        }
        trace('Setting beat callback filter to ${filter-1}');
        sequencer._setBeatCallbackFilter(filter - 1);
    }
    
    
    /** Force dispatch stream event. The SiONEvent.STREAM is dispatched only when the event listener is set BEFORE calling play(). You can let SiONDriver to dispatch SiONEvent.STREAM event by this function. 
     *  @param dispatch Set true to force dispatching. Or set false to not dispatching if there are no listeners.
     */
    public function forceDispatchStreamEvent(dispatch : Bool = true) : Void
    {
        _dispatchStreamEvent = dispatch || (Lib.current.hasEventListener(SiONEvent.STREAM));
    }
    
    
    
    // Interface for public data registration
    //----------------------------------------
    /** Set wave table data refered by %4.
     *  @param index wave table number.
     *  @param table wave shape vector ranges in -1 to 1.
     */
    public function setWaveTable(index : Int, table : Array<Float>) : SiOPMWaveTable
    {
        var len : Int;
        var bits : Int = -1;
        len = table.length;
        while (len > 0) {
            bits++;
            len >>= 1;
        }
        if (bits < 2) {
            return null;
        }
        var waveTable : Array<Int> = SiONUtil.logTransVector(table, 1, null);
        return SiOPMTable._instance.registerWaveTable(index, waveTable);
    }
    
    
    /** Set PCM wave data rederd by %7.
     *  @param index PCM data number.
     *  @param data wave data, Sound, Vector.&lt;Number&gt; or Vector.&lt;int&gt; is available. The Sound instance is extracted internally, the maximum length to extract is SiOPMWavePCMData.maxSampleLengthFromSound[samples].
     *  @param samplingNote Sampling wave's original note number, this allows decimal number
     *  @param keyRangeFrom Assigning key range starts from (not implemented in current version)
     *  @param keyRangeTo Assigning key range ends at (not implemented in current version)
     *  @param srcChannelCount channel count of source data, 1 for monoral, 2 for stereo.
     *  @param channelCount channel count of this data, 1 for monoral, 2 for stereo, 0 sets same with srcChannelCount.
     *  @see #org.si.sion.module.SiOPMWavePCMData.maxSampleLengthFromSound
     *  @see #render()
     */
    public function setPCMWave(index : Int, data : Dynamic, samplingNote : Float = 69, keyRangeFrom : Int = 0, keyRangeTo : Int = 127, srcChannelCount : Int = 2, channelCount : Int = 0) : SiOPMWavePCMData
    {
        var pcmVoice : SiMMLVoice = SiOPMTable._instance._getGlobalPCMVoice(index & (SiOPMTable.PCM_DATA_MAX - 1));
        var pcmTable : SiOPMWavePCMTable = try cast(pcmVoice.waveData, SiOPMWavePCMTable) catch(e:Dynamic) null;
        var samplerData = new SiOPMWavePCMData();
        samplerData.initializeFromSound(data, Math.floor(samplingNote * 64), srcChannelCount, channelCount);
        return pcmTable.setSample(samplerData, keyRangeFrom, keyRangeTo);
    }
    
    
    /** Set sampler wave data refered by %10.
     *  @param index note number. 0-127 for bank0, 128-255 for bank1.
     *  @param data wave data, Sound, Vector.&lt;Number&gt; or Vector.&lt;int&gt; is available. The Sound is extracted when the length is shorter than SiOPMWaveSamplerData.extractThreshold[msec].
     *  @param ignoreNoteOff True to set ignoring note off.
     *  @param pan pan of this sample [-64 - 64].
     *  @param srcChannelCount channel count of source data, 1 for monoral, 2 for stereo.
     *  @param channelCount channel count of this data, 1 for monoral, 2 for stereo, 0 sets same with srcChannelCount.
     *  @return created data instance
     *  @see #org.si.sion.module.SiOPMWaveSamplerData.extractThreshold
     *  @see #render()
     */
    public function setSamplerWave(index : Int, data : Dynamic, ignoreNoteOff : Bool = false, pan : Int = 0, srcChannelCount : Int = 2, channelCount : Int = 0) : SiOPMWaveSamplerData
    {
        return SiOPMTable._instance.registerSamplerData(index, data, ignoreNoteOff, pan, srcChannelCount, channelCount);
    }
    
    
    /** Set pcm voice 
     *  @param index PCM data number.
     *  @param voice pcm voice to set, ussualy from SiONSoundFont
     *  @see SiONSoundFont
     */
    public function setPCMVoice(index : Int, voice : SiONVoice) : Void
    {
        SiOPMTable._instance._setGlobalPCMVoice(index & (SiOPMTable.PCM_DATA_MAX - 1), voice);
    }
    
    
    /** Set sampler table 
     *  @param bank bank number
     *  @param table sampler table class, ussualy from SiONSoundFont
     *  @see SiONSoundFont
     */
    public function setSamplerTable(bank : Int, table : SiOPMWaveSamplerTable) : Void
    {
        SiOPMTable._instance.samplerTables[bank & (SiOPMTable.SAMPLER_TABLE_MAX - 1)] = table;
    }
    
    
    /** [NOT RECOMMENDED] This function is for a compatibility with previous versions, please use setPCMWave instead of this function. @see #setPCMWave(). */
    public function setPCMData(index : Int, data : Array<Float>, samplingOctave : Int = 5, keyRangeFrom : Int = 0, keyRangeTo : Int = 127, isSourceDataStereo : Bool = false) : SiOPMWavePCMData
    {
        return setPCMWave(index, data, samplingOctave * 12 + 9, keyRangeFrom, keyRangeTo, ((isSourceDataStereo)) ? 2 : 1);
    }
    
    
    /** [NOT RECOMMENDED] This function is for a compatibility with previous versions, please use setPCMWave instead of this function. @see #setPCMWave(). */
    public function setPCMSound(index : Int, sound : Sound, samplingOctave : Int = 5, keyRangeFrom : Int = 0, keyRangeTo : Int = 127) : SiOPMWavePCMData
    {
        return setPCMWave(index, sound, samplingOctave * 12 + 9, keyRangeFrom, keyRangeTo, 1, 0);
    }
    
    
    /** [NOT RECOMMENDED] This function is for a compatibility with previous versions, please use setSamplerWave instead of this function. @see #setSamplerWave(). */
    public function setSamplerData(index : Int, data : Array<Float>, ignoreNoteOff : Bool = false, channelCount : Int = 1) : SiOPMWaveSamplerData
    {
        return setSamplerWave(index, data, ignoreNoteOff, 0, channelCount);
    }
    
    
    /** [NOT RECOMMENDED] This function is for a compatibility with previous versions, please use setSamplerWave instead of this function. @see #setSamplerWave(). */
    public function setSamplerSound(index : Int, sound : Sound, ignoreNoteOff : Bool = false, channelCount : Int = 2) : SiOPMWaveSamplerData
    {
        return setSamplerWave(index, sound, ignoreNoteOff, 0, channelCount);
    }
    
    
    /** Set envelop table data refered by &#64;&#64;,na,np,nt,nf,_&#64;&#64;,_na,_np,_nt and _nf.
     *  @param index envelop table number.
     *  @param table envelop table vector.
     *  @param loopPoint returning point index of looping. -1 sets no loop.
     */
    public function setEnvelopTable(index : Int, table : Array<Int>, loopPoint : Int = -1) : Void
    {
        SiMMLTable.registerMasterEnvelopTable(index, new SiMMLEnvelopTable(table, loopPoint));
    }
    
    
    /** Set wave table data refered by %6.
     *  @param index wave table number.
     *  @param voice voice to register.
     */
    public function setVoice(index : Int, voice : SiONVoice) : Void
    {
        if (!voice._isSuitableForFMVoice)             throw errorNotGoodFMVoice();
        SiMMLTable.registerMasterVoice(index, voice);
    }
    
    
    /** Clear all of WaveTables, FM Voices, EnvelopTables, Sampler waves and PCM waves. 
     *  @see #setWaveTable()
     *  @see #setVoice()
     *  @see #setEnvelopTable()
     *  @see #setSamplerWave()
     *  @see #setPCMWave()
     */
    public function clearAllUserTables() : Void
    {
        SiOPMTable.instance.resetAllUserTables();
        SiMMLTable.instance.resetAllUserTables();
    }
    
    
    
    
    // Interface for intaractivity
    //----------------------------------------
    /** Play sound registered in sampler table (registered by setSamplerData()), same as noteOn(note, new SiONVoice(10), ...).
     *  @param sampleNumber sample number [0-127].
     *  @param length note length in 16th beat. 0 sets no note off, this means you should call noteOff().
     *  @param delay note on delay units in 16th beat.
     *  @param quant quantize in 16th beat. 0 sets no quantization. 4 sets quantization by 4th beat.
     *  @param trackID new tracks id (0-65535).
     *  @param isDisposable use disposable track. The disposable track will free automatically when finished rendering. 
     *         This means you should not keep a dieposable track in your code perpetually. 
     *         If you want to keep track, set this argument falsesetDisposal() to disposed by system.<br/>
     *         [REMARKS] Not disposable track is kept perpetually in the system while streaming, this may causes critical performance loss.
     *  @return SiMMLTrack to play the note. 
     */
    public function playSound(sampleNumber : Int,
            length : Float = 0,
            delay : Float = 0,
            quant : Float = 0,
            trackID : Int = 0,
            isDisposable : Bool = true) : SiMMLTrack
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.DRIVER_NOTE;
        var mmlTrack : SiMMLTrack = null;
        var delaySamples : Float = sequencer.calcSampleDelay(0, delay, quant);
        
        // check track id exception
        if (_noteOnExceptionMode != NEM_IGNORE) {
            // find a track sounds at same timing
            mmlTrack = sequencer._findActiveTrack(internalTrackID, Math.floor(delaySamples));
            if (_noteOnExceptionMode == NEM_REJECT && mmlTrack != null)                 return null
            // reject
            else if (_noteOnExceptionMode == NEM_SHIFT) {  // shift timing  
                var step : Int = Math.floor(sequencer.calcSampleLength(quant));
                while (mmlTrack != null) {
                    delaySamples += step;
                    mmlTrack = sequencer._findActiveTrack(internalTrackID, Math.floor(delaySamples));
                }
            }
        }
        
        if (mmlTrack == null) sequencer._newControlableTrack(internalTrackID, isDisposable);
        if (mmlTrack != null) {
            mmlTrack.setChannelModuleType(10, 0);
            mmlTrack.keyOn(sampleNumber, Math.floor(length * sequencer.setting.resolution * 0.0625),
                           Math.floor(delaySamples));
        }
        return mmlTrack;
    }
    
    
    /** Note on. This function only is available after play(). The NOTE_ON_STREAM event is dispatched inside.
     *  @param note note number [0-127].
     *  @param voice SiONVoice to play note. You can specify null, but it sets only a default square wave.
     *  @param length note length in 16th beat. 0 sets no note off, this means you should call noteOff().
     *  @param delay note on delay units in 16th beat.
     *  @param quant quantize in 16th beat. 0 sets no quantization. 4 sets quantization by 4th beat.
     *  @param trackID new tracks id (0-65535).
     *  @param isDisposable use disposable track. The disposable track will free automatically when finished rendering. 
     *         This means you should not keep a dieposable track in your code perpetually. 
     *         If you want to keep track, set this argument falsesetDisposal() to disposed by system.<br/>
     *         [REMARKS] Not disposable track is kept in the system perpetually while streaming, this may causes critical performance loss.
     *  @return SiMMLTrack to play the note.
     */
    public function noteOn(note : Int,
            voice : SiONVoice = null,
            length : Float = 0,
            delay : Float = 0,
            quant : Float = 0,
            trackID : Int = 0,
            isDisposable : Bool = true) : SiMMLTrack
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.DRIVER_NOTE;
        var mmlTrack : SiMMLTrack = null;
        var delaySamples : Float = sequencer.calcSampleDelay(0, delay, quant);
        
        // check track id exception
        if (_noteOnExceptionMode != NEM_IGNORE) {
            // find a track sounds at same timing
            mmlTrack = sequencer._findActiveTrack(internalTrackID, Math.floor(delaySamples));
            if (_noteOnExceptionMode == NEM_REJECT && mmlTrack != null)                 return null
            // reject
            else if (_noteOnExceptionMode == NEM_SHIFT) {  // shift timing  
                var step : Int = Math.floor(sequencer.calcSampleLength(Math.floor(quant)));
                while (mmlTrack != null){
                    delaySamples += step;
                    mmlTrack = sequencer._findActiveTrack(internalTrackID, Math.floor(delaySamples));
                }
            }
        }
        
        if (mmlTrack == null) mmlTrack = sequencer._newControlableTrack(internalTrackID, isDisposable);
        if (mmlTrack != null) {
            if (voice != null)                 voice.updateTrackVoice(mmlTrack);
            mmlTrack.keyOn(note, Math.floor(length * sequencer.setting.resolution * 0.0625), Math.floor(delaySamples));
        }
        return mmlTrack;
    }
    
    
    /** Note off. This function only is available after play(). The NOTE_OFF_STREAM event is dispatched inside.
     *  @param note note number [-1-127]. The value of -1 ignores note number.
     *  @param trackID track id to note off.
     *  @param delay note off delay units in 16th beat.
     *  @param quant quantize in 16th beat. 0 sets no quantization. 4 sets quantization by 4th beat.
     *  @param stopImmediately stop sound with reseting channel's process
     *  @return All SiMMLTracks switched key off.
     */
    public function noteOff(note : Int, trackID : Int = 0, delay : Float = 0, quant : Float = 0, stopImmediately : Bool = false) : Array<SiMMLTrack>
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.DRIVER_NOTE;
        var delaySamples : Int = Math.floor(sequencer.calcSampleDelay(0, delay, quant));
        var n : Int;
        var tracks : Array<SiMMLTrack> = new Array<SiMMLTrack>();
        for (mmlTrack/* AS3HX WARNING could not determine type for var: mmlTrack exp: EField(EIdent(sequencer),tracks) type: null */ in sequencer.tracks){
            if (mmlTrack._internalTrackID == internalTrackID) {
                if (note == -1 || (note == mmlTrack.note && mmlTrack.channel.isNoteOn)) {
                    mmlTrack.keyOff(delaySamples, stopImmediately);
                    tracks.push(mmlTrack);
                }
                else if (mmlTrack.executor.noteWaitingFor == note) {
                    // if this track is waiting for starting sound ...
                    mmlTrack.keyOn(note, 1, delaySamples);
                    tracks.push(mmlTrack);
                }
            }
        }
        return tracks;
    }
    
    
    /** Play sequences with synchronizing. This function only is available after play(). 
     *  @param data The SiONData including sequences. This data is used only for sequences. The system ignores wave, envelop and voice data.
     *  @param voice SiONVoice to play sequence. The voice setting in the sequence has priority.
     *  @param length note length in 16th beat. 0 sets no note off, this means you should call noteOff().
     *  @param delay note on delay units in 16th beat.
     *  @param quant quantize in 16th beat. 0 sets no quantization. 4 sets quantization by 4th beat.
     *  @param trackID new tracks id (0-65535).
     *  @param isDisposable use disposable track. The disposable track will free automatically when finished rendering. 
     *         This means you should not keep a dieposable track in your code perpetually. 
     *         If you want to keep track, set this argument falsesetDisposal() to disposed by system.<br/>
     *         [REMARKS] Not disposable track is kept in the system perpetually while streaming, this may causes critical performance loss.
     *  @return list of SiMMLTracks to play sequence.
     */
    public function sequenceOn(data : SiONData,
            voice : SiONVoice = null,
            length : Float = 0,
            delay : Float = 0,
            quant : Float = 1,
            trackID : Int = 0,
            isDisposable : Bool = true) : Array<SiMMLTrack>
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.DRIVER_SEQUENCE;
        var mmlTrack : SiMMLTrack;
        var tracks : Array<SiMMLTrack> = new Array<SiMMLTrack>();
        var seq : MMLSequence = data.sequenceGroup.headSequence;
        var delaySamples : Int = Math.floor(sequencer.calcSampleDelay(0, delay, quant));
        var lengthSamples : Int = Math.floor(sequencer.calcSampleLength(length));

        trace('sequenceOn, seq is $seq delay $delaySamples length $lengthSamples');
        // create new sequence tracks
        while (seq != null){
            trace('We have a sequence.');
            if (seq.isActive) {
                trace('Sequence is active');
                mmlTrack = sequencer._newControlableTrack(internalTrackID, isDisposable);
                mmlTrack.sequenceOn(seq, lengthSamples, delaySamples);
                if (voice != null) {
                    trace('And we have a voice!');
                    voice.updateTrackVoice(mmlTrack);
                }
                tracks.push(mmlTrack);
            }
            seq = seq.nextSequence;
        }
        trace('Returning $tracks');
        return tracks;
    }
    
    
    /** Stop the sequences with synchronizing. This function only is available after play(). 
     *  @param trackID tracks id to stop.
     *  @param delay sequence off delay units in 16th beat.
     *  @param quant quantize in 16th beat. 0 sets no quantization. 4 sets quantization by 4th beat.
     *  @param stopWithReset stop sound with reseting channel's process
     *  @return list of SiMMLTracks stopped to play sequence.
     */
    public function sequenceOff(trackID : Int, delay : Float = 0, quant : Float = 1, stopWithReset : Bool = false) : Array<SiMMLTrack>
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.DRIVER_SEQUENCE;
        var delaySamples : Int = Math.floor(sequencer.calcSampleDelay(0, delay, quant));
        var stoppedTrack : SiMMLTrack = null;
        var tracks : Array<SiMMLTrack> = new Array<SiMMLTrack>();
        for (mmlTrack/* AS3HX WARNING could not determine type for var: mmlTrack exp: EField(EIdent(sequencer),tracks) type: null */ in sequencer.tracks){
            if (mmlTrack._internalTrackID == internalTrackID) {
                mmlTrack.sequenceOff(delaySamples, stopWithReset);
                tracks.push(mmlTrack);
            }
        }
        return tracks;
    }
    
    
    /** Create new user controlable track. This function only is available after play(). 
     *  @trackID new user controlable track's ID.
     *  @return new user controlable track. This track is NOT disposable.
     */
    public function newUserControlableTrack(trackID : Int = 0) : SiMMLTrack
    {
        var internalTrackID : Int = (trackID & SiMMLTrack.TRACK_ID_FILTER) | SiMMLTrack.USER_CONTROLLED;
        return sequencer._newControlableTrack(internalTrackID, false);
    }
    
    
    /** dispatch SiONTrackEvent.USER_DEFINED event with latency delay 
     *  @param eventTriggerID SiONTrackEvent.eventTriggerID
     *  @param note SiONTrackEvent.note
     */
    public function dispatchUserDefinedTrackEvent(eventTriggerID : Int, note : Int) : Void
    {
        var event : SiONTrackEvent = new SiONTrackEvent(SiONTrackEvent.USER_DEFINED, this, null, sequencer.streamWritingPositionResidue, note, eventTriggerID);
        _trackEventQueue.push(event);
    }
    
    
    
    
    //====================================================================================================
    // Internal uses
    //====================================================================================================
    // callback for event trigger
    //----------------------------------------
    // call back when sound streaming
    private function _callbackEventTriggerOn(track : SiMMLTrack) : Bool
    {
        return _publishEventTrigger(track, track.eventTriggerTypeOn, SiONTrackEvent.NOTE_ON_FRAME, SiONTrackEvent.NOTE_ON_STREAM);
    }
    
    // call back when sound streaming
    private function _callbackEventTriggerOff(track : SiMMLTrack) : Bool
    {
        return _publishEventTrigger(track, track.eventTriggerTypeOff, SiONTrackEvent.NOTE_OFF_FRAME, SiONTrackEvent.NOTE_OFF_STREAM);
    }
    
    // publish event trigger
    private function _publishEventTrigger(track : SiMMLTrack, type : Int, frameEvent : String, streamEvent : String) : Bool
    {
        var event : SiONTrackEvent;
        if ((type & 1) != 0) {
            // frame event. dispatch later
            event = new SiONTrackEvent(frameEvent, this, track);
            _trackEventQueue.push(event);
        }
        if ((type & 2) != 0) {  // sound event. dispatch immediately
            event = new SiONTrackEvent(streamEvent, this, track);
            dispatchEvent(event);
            return !(event.isDefaultPrevented());
        }
        return true;
    }
    
    // call back when tempo changed
    private function _callbackTempoChanged(bufferIndex : Int, isDummy : Bool) : Void
    {
        if (isDummy && _dispatchChangeBPMEventWhenPositionChanged) {
            dispatchEvent(new SiONTrackEvent(SiONTrackEvent.CHANGE_BPM, this, null, bufferIndex));
        }
        else {
            var event : SiONTrackEvent = new SiONTrackEvent(SiONTrackEvent.CHANGE_BPM, this, null, bufferIndex);
            _trackEventQueue.push(event);
        }
    }
    
    // call back on beat
    private function _callbackBeat(bufferIndex : Int, beatCounter : Int) : Void
    {
        var event : SiONTrackEvent = new SiONTrackEvent(SiONTrackEvent.BEAT, this, null, bufferIndex, 0, beatCounter);
        _trackEventQueue.push(event);
    }
    
    
    
    
    // operate event listener
    //----------------------------------------
    // add all event listners
    private function _queue_addAllEventListners() : Void
    {
        if (_listenEvent != NO_LISTEN)             throw errorDriverBusy(LISTEN_QUEUE);
         Lib.current.addEventListener(Event.ENTER_FRAME, _queue_onEnterFrame, false, _eventListenerPrior);
        _listenEvent = LISTEN_QUEUE;
    }
    
    
    // add all event listners
    private function _process_addAllEventListners() : Void
    {
        trace('@@@@@@@@@@ Adding all event listeners!!');
        if (_listenEvent != NO_LISTEN) throw errorDriverBusy(LISTEN_PROCESS);
        Lib.current.addEventListener(Event.ENTER_FRAME, _process_onEnterFrame, false, _eventListenerPrior);
        if (Lib.current.hasEventListener(SiONTrackEvent.BEAT)) sequencer._setBeatCallback(_callbackBeat)
        else sequencer._setBeatCallback(null);
        _dispatchStreamEvent = (Lib.current.hasEventListener(SiONEvent.STREAM));
        _prevFrameTime = Math.round(haxe.Timer.stamp() * 1000);
        _listenEvent = LISTEN_PROCESS;
    }
    
    
    // remove all event listners
    private function _removeAllEventListners() : Void
    {
        switch (_listenEvent)
        {
            case LISTEN_QUEUE:
                Lib.current.removeEventListener(Event.ENTER_FRAME, _queue_onEnterFrame);
            case LISTEN_PROCESS:
                trace('@@@@@@@@@@ Removing ENTER_FRAME listener.');
                Lib.current.removeEventListener(Event.ENTER_FRAME, _process_onEnterFrame);
                sequencer._setBeatCallback(null);
                _dispatchStreamEvent = false;
        }
        _listenEvent = NO_LISTEN;
    }
    
    
    // handler for Sound COMPLETE/IO_ERROR Event
    private function _onSoundEvent(e : Event) : Void
    {
        if (Std.is(e.target, Sound)) {
            e.target.removeEventListener(Event.COMPLETE, _onSoundEvent);
            e.target.removeEventListener(IOErrorEvent.IO_ERROR, _onSoundEvent);
        }
        else {  // e.target is SoundLoader  
            e.target.removeEventListener(Event.COMPLETE, _onSoundEvent);
            e.target.removeEventListener(ErrorEvent.ERROR, _onSoundEvent);
        }
        var i : Int = Lambda.indexOf(_loadingSoundList, e.target);
        if (i != -1)             _loadingSoundList.splice(i, 1);
    }
    
    
    
    
    // parse
    //----------------------------------------
    // parse system command on SiONDriver
    private function _parseSystemCommand(systemCommands : Array<Dynamic>) : Bool
    {
        var id : Int;
        var wcol : Int;
        var effectSet : Bool = false;
        for (cmd in systemCommands){
            var _sw0_ = (cmd.command);            

            switch (_sw0_)
            {
                case "#EFFECT":
                    effectSet = true;
                    effector.parseMML(cmd.number, cmd.content, cmd.postfix);
                case "#WAVCOLOR", "#WAVC":
                    wcol = Std.parseInt("0x" + cmd.content);
                    setWaveTable(cmd.number, SiONUtil.waveColor(wcol));
            }
        }
        return effectSet;
    }
    
    
    
    
    // jobs queue
    //----------------------------------------
    // cancel
    private function _cancelAllJobs() : Void
    {
        _data = null;
        _mmlString = null;
        _currentJob = 0;
        _jobProgress = 0;
        _jobQueue.splice(0,_jobQueue.length);
        _queueLength = 0;
        _removeAllEventListners();
        dispatchEvent(new SiONEvent(SiONEvent.QUEUE_CANCEL, this, null));
    }
    
    
    // next job
    private function _executeNextJob() : Bool
    {
        _data = null;
        _mmlString = null;
        _currentJob = 0;
        if (_jobQueue.length == 0) {
            _queueLength = 0;
            _removeAllEventListners();
            dispatchEvent(new SiONEvent(SiONEvent.QUEUE_COMPLETE, this, null));
            return true;
        }
        
        var queue : SiONDriverJob = _jobQueue.shift();
        if (queue.mml != null) _prepareCompile(queue.mml, queue.data)
        else _prepareRender(queue.data, queue.buffer, queue.channelCount, queue.resetEffector);
        return false;
    }
    
    
    // on enterFrame
    private function _queue_onEnterFrame(e : Event) : Void
    {
        try{
            var event : SiONEvent;
            var t : Int = Math.round(haxe.Timer.stamp() * 1000);
            
            switch (_currentJob)
            {
                case 1:  // compile  
                    _jobProgress = sequencer.compile(_queueInterval);
                    _timeCompile += Math.round(haxe.Timer.stamp() * 1000) - t;
                case 2:  // render  
                    _jobProgress += (1 - _jobProgress) * 0.5;
                    while (Math.round(haxe.Timer.stamp() * 1000) - t <= _queueInterval){
                        if (_rendering()) {
                            _jobProgress = 1;
                            break;
                        }
                    }
                    _timeRender += Math.round(haxe.Timer.stamp() * 1000) - t;
            }

            // finish job
            if (_jobProgress == 1) {
                // finish all jobs
                if (_executeNextJob()) return;
            }

            // progress
            event = new SiONEvent(SiONEvent.QUEUE_PROGRESS, this, null, true);
            dispatchEvent(event);
            // canceled
            if (event.isDefaultPrevented())  _cancelAllJobs();
        }
        catch (e : Error) {
            trace('error in queue enter frame: $e');
            // error
            _removeAllEventListners();
            _cancelAllJobs();
            if (_debugMode) throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }
    }
    
    
    
    
    // compile
    //----------------------------------------
    // prepare to compile
    private function _prepareCompile(mml : String, data : SiONData) : Void
    {
        if (data != null) {
            data.clear();
        }
        _data = data;
        if (_data == null) {
            _data = new SiONData();
        }
        _mmlString = mml;
        trace('SDR.prepareCompile($_data, $_mmlString)');
        trace('sequencer is $sequencer');
        sequencer.prepareCompile(_data, _mmlString);
        trace('sequencer done preparing.');
        _jobProgress = 0.01;
        _timeCompile = 0;
        _currentJob = 1;
    }
    
    
    
    
    // render
    //----------------------------------------
    // prepare for rendering
    private function _prepareRender(data : Dynamic, renderBuffer : Array<Float>, renderBufferChannelCount : Int, resetEffector : Bool) : Void
    {
        // same preparation as streaming
        _prepareProcess(data, resetEffector);
        
        // prepare rendering buffer
        if (_renderBuffer == null) renderBuffer = new Array<Float>();
        _renderBufferChannelCount = ((renderBufferChannelCount == 2)) ? 2 : 1;
        _renderBufferSizeMax = _renderBuffer.length;
        _renderBufferIndex = 0;
        
        // initialize parameters
        _jobProgress = 0.01;
        _timeRender = 0;
        _currentJob = 2;
    }
    
    
    // rendering @return true when finished rendering.
    private function _rendering() : Bool
    {
        var i : Int;
        var j : Int;
        var imax : Int;
        var extention : Int;
        var output : Array<Float> = module.output;
        var finished : Bool = false;
        
        // processing
        module._beginProcess();
        effector._beginProcess();
        sequencer._process();
        effector._endProcess();
        module._endProcess();
        
        // limit rendering length
        imax = _bufferLength << 1;
        extention = _bufferLength << (_renderBufferChannelCount - 1);
        if (_renderBufferSizeMax != 0 && _renderBufferSizeMax < _renderBufferIndex + extention) {
            extention = _renderBufferSizeMax - _renderBufferIndex;
            finished = true;
        }

        // copy output
        if (_renderBufferChannelCount == 2) {
            i = 0;
            j = _renderBufferIndex;
            while (i < imax){
                _renderBuffer[j] = output[i];
                i++;
                j++;
            }
        }
        else {
            i = 0;
            j = _renderBufferIndex;
            while (i < imax){
                _renderBuffer[j] = output[i];
                i += 2;
                j++;
            }
        }

        // incerement index
        _renderBufferIndex += extention;

        return (finished || (_renderBufferSizeMax == 0 && sequencer.isFinished));
    }
    
    
    
    
    // process
    //----------------------------------------
    // prepare for processing
    private function _prepareProcess(data : Dynamic, resetEffector : Bool) : Void
    {
        trace('SDR._prepareProcess()');
        if (data != null) {
            if (Std.is(data, String)) {  // mml
                trace('Type of data is string');
                // compile mml and play
                if (_tempData == null) _tempData = new SiONData();
                trace('tempdata is $_tempData');
                var stringData = try cast(data, String) catch(e:Dynamic) null;
                trace('stringdata is $stringData');
                _data = compile(stringData, _tempData);
                trace('_data is $_data');
            }
            else if (Std.is(data, SiONData)) {
                trace('Type of data is SiONData.');
                // type check and play
                _data = data;
            }
            else if (Std.is(data, Sound)) {
                trace('Type of data is Sound.');
                // play data as background sound
                setBackgroundSound(data);
            }
            else if (Std.is(data, URLRequest)) {
                trace('Type of data is URLRequest.');
                // load sound from url
                var sound : Sound = new Sound(data);
                setBackgroundSound(sound);
            }
#if MIDI_ENABLED
            else if (Std.is(data, SMFData)) {
                trace('Type of data is MIDI SMFData.');
                // MIDI file
                _midiConverter.smfData = data;
                _midiConverter.useMIDIModuleEffector = resetEffector;
                _data = _midiConverter;
            }
#end
            else {
#if !MIDI_ENABLED
            trace("***** MIDI is currently unsupported");
#end
                trace('Type of data is unknown.');
                // not good data type
                throw errorDataIncorrect();
            }
        } else {
            trace('No data to play');
        }

        // THE ORDER OF THESE FUNCTIONS IS VERY IMPORTANT !!
        // initialize DSP
        module.initialize(_channelCount, _bitRate, _bufferLength);
        // reset all channels
        module.reset();
        // initialize (or reset) effectors
        if (resetEffector) {
            effector.initialize();
        }
        else {
            effector._reset();
        }
        // set sequencer tracks (should be called after module.reset())
        sequencer._prepareProcess(_data, _sampleRate, _bufferLength);
        // parse #EFFECT command (should be called after effector._reset())
        if (_data != null) {
            _parseSystemCommand(_data.systemCommands);
        }
        // set effector connections
        effector._prepareProcess();
        // clear event queue
        _trackEventQueue.splice(0, _trackEventQueue.length);

        // set position
        if (_data != null && _position > 0) {
            sequencer.dummyProcess(Math.round(_position * _sampleRate * 0.001));
        }

        // start background sound
        if (_backgroundSound != null) {
            _startBackgroundSound();
        }

        trace('Timer callback is $_timerCallback');
        // set timer interruption
        if (_timerCallback != null) {
            sequencer.setGlobalSequence(_timerSequence);  // set timer interruption
            sequencer._setTimerCallback(_timerCallback);
        }
    }
    
    
    // on enterFrame
    private function _process_onEnterFrame(e : Event) : Void
    {
        // frame rate
        var t : Int = Math.round(haxe.Timer.stamp() * 1000);
        _frameRate = t - _prevFrameTime;
        _prevFrameTime = t;
        
        // _suspendStreaming = true when first streaming
        if (_suspendStreaming) {
            _onSuspendStream();
        }
        else {
            // preserve stop
            if (_preserveStop) {
                trace('preserveStop is set');
                stop();
            }


            // frame trigger
            if (_trackEventQueue.length > 0) {
                _trackEventQueue = _trackEventQueue.filter(_trackEventQueueFilter);
            }
        }
    }
    
    
    // _trackEventQueue filter
    private function _trackEventQueueFilter(e : SiONTrackEvent) : Bool{
        if (e._decrementTimer(_frameRate)) {
            dispatchEvent(e);
            return false;
        }
        return true;
    }
    
    
    // suspend starting stream
    private function _onSuspendStream() : Void {
        trace('onSuspendStream()');
        // reset suspending
        _suspendStreaming = _suspendWhileLoading && (_loadingSoundList.length > 0);
        trace('  suspendStreaming reset to $_suspendStreaming');

        if (!_suspendStreaming) {
            // dispatch streaming start event
            var event : SiONEvent = new SiONEvent(SiONEvent.STREAM_START, this, null, true);
            dispatchEvent(event);
            if (event.isDefaultPrevented()) stop();    // canceled
        }
    }


    private var time : Float = haxe.Timer.stamp();

    // on sampleData
    private function _streaming(e : SampleDataEvent) : Void
    {
        var now = haxe.Timer.stamp();
        //trace('Time since last: ${(now - time) * 1000} ms');
        time = now;

        if (e.data == null) {
            e.data = new ByteArray();
			e.data.endian = Endian.LITTLE_ENDIAN;
        }
        var buffer : ByteArray = e.data;
        var extracted : Int;
        var output : Array<Float> = module.output;
        var imax : Int;
        var i : Int;
        var event : SiONEvent;
        
        // calculate latency (0.022675736961451247 = 1/44.1)
        if (_soundChannel != null) {
            _latency = e.position * 0.022675736961451247 - _soundChannel.position;
        }
        
        try{
            // set streaming flag
            _inStreaming = true;
            
            if (_isPaused || _suspendStreaming) {
                //trace('Streaming is paused: $_isPaused or suspended: $_suspendStreaming');
                // fill silence
                _fillzero(e.data);
            }
            else {
                //trace('Streaming audio data...');

                // process starting time
                var t : Int = Math.round(haxe.Timer.stamp() * 1000);
                
                // processing
                module._beginProcess();
                effector._beginProcess();
                sequencer._process();
                effector._endProcess();
                module._endProcess();
                
                // calculate average of processing time
                _timePrevStream = t;
                _timeProcessTotal -= _timeProcessData.i;
                _timeProcessData.i = Math.round(haxe.Timer.stamp() * 1000) - t;
                _timeProcessTotal += _timeProcessData.i;
                _timeProcessData = _timeProcessData.next;
                _timeProcess = Math.floor(_timeProcessTotal * _timeProcessAveRatio);
                
                // write samples
                imax = output.length;
                var lastData : Float = 0.0;
                //if (imax > 0 && imax < 4096)
                //    trace('***** Writing $imax samples');
                for (i in 0...imax) {
                    buffer.writeFloat(output[i]);
                    lastData = output[i];
                }
                // Test to fill in the buffer
                if (imax == 0) {
                    for (i in imax...4096) {
                        buffer.writeFloat(lastData);
                    }
                }

                // dispatch streaming event
                if (_dispatchStreamEvent) {
                    event = new SiONEvent(SiONEvent.STREAM, this, buffer, true);
                    dispatchEvent(event);
                    if (event.isDefaultPrevented()) {
                        trace('is default prevented');
                        stop();  // canceled
                    }
                }

                // dispatch finishSequence event
                if (!_isFinishSeqDispatched && sequencer.isSequenceFinished) {
                    dispatchEvent(new SiONEvent(SiONEvent.FINISH_SEQUENCE, this));
                    _isFinishSeqDispatched = true;
                }

                // fading
                if (_fader.execute()) {
                    var eventType : String = ((_fader.isIncrement)) ? SiONEvent.FADE_IN_COMPLETE : SiONEvent.FADE_OUT_COMPLETE;
                    dispatchEvent(new SiONEvent(eventType, this, buffer));
                    if (_autoStop && !_fader.isIncrement) {
                        trace('fader says stop');
                        stop();
                    }
                }
                else {
                    // auto stop
                    if (_autoStop && sequencer.isFinished) {
                        trace('we are done and auto stopping');
                        stop();
                    }
                }
            }

            // reset streaming flag
            _inStreaming = false;
        }
        catch (e : Error) {
            trace('Error streaming data: $e');
            // error
            _removeAllEventListners();
            if (_debugMode) throw e
            else dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.message));
        }

        //var end = haxe.Timer.stamp();
        //trace('Time to write samples: ${(end - now) * 1000} ms');
    }
    
    
    // fill zero
    private function _fillzero(buffer : ByteArray) : Void{
        var i : Int;
        var imax : Int = _bufferLength;
        for (i in 0...imax){
            buffer.writeFloat(0);
            buffer.writeFloat(0);
        }
    }



#if MIDI_ENABLED

    // MIDI related
    //----------------------------------------
    /** @private dispatch SiONMIDIEvent call from MIDIModule */
    private function _checkMIDIEventListeners() : Int
    {
        return (((Lib.current.hasEventListener(SiONMIDIEvent.NOTE_ON))) ? SiONMIDIEventFlag.NOTE_ON : 0) |
        (((Lib.current.hasEventListener(SiONMIDIEvent.NOTE_OFF))) ? SiONMIDIEventFlag.NOTE_OFF : 0) |
        (((Lib.current.hasEventListener(SiONMIDIEvent.CONTROL_CHANGE))) ? SiONMIDIEventFlag.CONTROL_CHANGE : 0) |
        (((Lib.current.hasEventListener(SiONMIDIEvent.PROGRAM_CHANGE))) ? SiONMIDIEventFlag.PROGRAM_CHANGE : 0) |
        (((Lib.current.hasEventListener(SiONMIDIEvent.PITCH_BEND))) ? SiONMIDIEventFlag.PITCH_BEND : 0);
    }
    
    
    /** @private dispatch SiONMIDIEvent call from MIDIModule */
    private function _dispatchMIDIEvent(type : String, track : SiMMLTrack, channelNumber : Int, note : Int, data : Int) : Void
    {
        var event : SiONMIDIEvent = new SiONMIDIEvent(type, this, track, channelNumber, sequencer.streamWritingPositionResidue, note, data);
        _trackEventQueue.push(event);
    }
#end
    
    
    
    // operations
    //----------------------------------------
    // volume fading
    private function _fadeVolume(v : Float) : Void{
        _faderVolume = v;
        _soundTransform.volume = _masterVolume * _faderVolume;
        if (_soundChannel != null)             _soundChannel.soundTransform = _soundTransform;
        if (_dispatchFadingEvent) {
            var event : SiONEvent = new SiONEvent(SiONEvent.FADE_PROGRESS, this, null, true);
            dispatchEvent(event);
            if (event.isDefaultPrevented()) _fader.stop();  // canceled
        }
    }
    
    
    
    
    // baclkground sound
    //----------------------------------------
    // 1st internal entry point (pass null to stop sound)
    private function _setBackgroundSound(sound : Sound) : Void{
        if (sound != null) {
            if ((sound.bytesTotal == 0) || (cast(sound.bytesLoaded, UInt) != cast(sound.bytesTotal,UInt))) {
                sound.addEventListener(Event.COMPLETE, _onBackgroundSoundLoaded);
                sound.addEventListener(IOErrorEvent.IO_ERROR, _errorBackgroundSound);
            }
            else {
                _backgroundSound = sound;
                if (isPlaying)                     _startBackgroundSound();
            }
        }
        else {
            // stop
            _backgroundSound = null;
            if (isPlaying)                 _startBackgroundSound();
        }
    }
    
    
    // on loaded
    private function _onBackgroundSoundLoaded(e : Event) : Void{
        _backgroundSound = try cast(e.target, Sound) catch(e:Dynamic) null;
        if (isPlaying)             _startBackgroundSound();
    }
    
    
    // start
    private function _startBackgroundSound() : Void{
        // frame index of start and end fading
        var startFrame : Int;
        var endFrame : Int;
        
        // currently fading out -> stop fade out track
        if (_backgroundTrackFadeOut != null) {
            _backgroundTrackFadeOut.setDisposable();
            _backgroundTrackFadeOut.keyOff(0, true);
            _backgroundTrackFadeOut = null;
        }  // background sound is playing now -> fade out  
        
        if (_backgroundTrack != null) {
            _backgroundTrackFadeOut = _backgroundTrack;
            _backgroundTrack = null;
            startFrame = 0;
        }
        else {
            // no fadeout
            startFrame = _backgroundFadeOutFrames + _backgroundFadeGapFrames;
        }
        
        if (_backgroundSound != null) {
            // play sound with fade in
            _backgroundSample = new SiOPMWaveSamplerData();
            _backgroundSample.initializeFromSound(_backgroundSound, true, 0, 2, 2);
            _backgroundVoice.waveData = _backgroundSample;
            if (_backgroundLoopPoint != -1) {
                _backgroundSample.slice(-1, -1, Std.int(_backgroundLoopPoint * 44100));
            }
            _backgroundTrack = sequencer._newControlableTrack(SiMMLTrack.DRIVER_BACKGROUND, false);
            _backgroundTrack.expression = 128;
            _backgroundVoice.updateTrackVoice(_backgroundTrack);
            _backgroundTrack.keyOn(60, 0, (_backgroundFadeOutFrames + _backgroundFadeGapFrames) * _bufferLength);
            endFrame = _backgroundTotalFadeFrames;
        }
        else {
            // no new sound
            _backgroundSample = null;
            _backgroundVoice.waveData = null;
            _backgroundLoopPoint = -1;
            endFrame = _backgroundFadeOutFrames + _backgroundFadeGapFrames;
        }  // set fader  
        
        
        
        if (endFrame - startFrame > 0) {
            _fader.setFade(_fadeBackgroundSound, startFrame, endFrame, endFrame - startFrame);
        }
        else {
            // stop fade out immediately
            if (_backgroundTrackFadeOut != null) {
                _backgroundTrackFadeOut.setDisposable();
                _backgroundTrackFadeOut.keyOff(0, true);
                _backgroundTrackFadeOut = null;
            }
        }
    }
    
    
    // error
    private function _errorBackgroundSound(e : IOErrorEvent) : Void{
        _backgroundSound = null;
        throw errorSoundLoadingFailure();
    }
    
    
    // background sound cross fading
    private function _fadeBackgroundSound(v : Float) : Void{
        var fo : Float = 1;
        var fi : Float = 0;
        if (_backgroundTrackFadeOut != null) {
            if (_backgroundFadeOutFrames > 0) {
                fo = 1 - v / _backgroundFadeOutFrames;
                if (fo < 0)                     fo = 0
                else if (fo > 1)                     fo = 1;
            }
            else {
                fo = 0;
            }
            _backgroundTrackFadeOut.expression = Math.floor(fo * 128);
        }
        if (_backgroundTrack != null) {
            if (_backgroundFadeInFrames > 0) {
                fi = 1 - (_backgroundTotalFadeFrames - v) / _backgroundFadeInFrames;
                if (fi < 0)                     fi = 0
                else if (fi > 1)                     fi = 1;
            }
            else {
                fi = 1;
            }
            _backgroundTrack.expression = Math.floor(fi * 128);
        }
        if (_backgroundTrackFadeOut != null && (fo == 0 || fi == 1)) {
            _backgroundTrackFadeOut.setDisposable();
            _backgroundTrackFadeOut.keyOff(0, true);
            _backgroundTrackFadeOut = null;
        }
    }
    
    
    
    
    
    // errors
    //----------------------------------------
    private function errorPluralDrivers() : Error{
        return new Error("SiONDriver error; Cannot create plural SiONDrivers.");
    }
    
    
    private function errorParamNotAvailable(param : String, num : Float) : Error{
        return new Error("SiONDriver error; Parameter not available. " + param + Std.string(num));
    }
    
    
    private function errorDataIncorrect() : Error{
        return new Error("SiONDriver error; data incorrect in play() or render().");
    }
    
    
    private function errorDriverBusy(execID : Int) : Error{
        var states : Array<Dynamic> = ["???", "compiling", "streaming", "rendering"];
        return new Error("SiONDriver error: Driver busy. Call " + states[execID] + " while " + states[_listenEvent] + ".");
    }
    
    
    private function errorCannotChangeBPM() : Error{
        return new Error("SiONDriver error: Cannot change bpm while rendering (SiONTrackEvent.NOTE_*_STREAM).");
    }
    
    
    private function errorNotGoodFMVoice() : Error{
        return new Error("SiONDriver error; Cannot register the voice.");
    }
    
    
    private function errorCannotListenLoading() : Error{
        return new Error("SiONDriver error; the class not available for listenSoundLoadingStatus");
    }
    
    
    private function errorSoundLoadingFailure() : Error{
        return new Error("SiONDriver error; fail to load the sound file");
    }
}






class SiONDriverJob
{
    public var mml : String;
    public var buffer : Array<Float>;
    public var data : SiONData;
    public var channelCount : Int;
    public var resetEffector : Bool;
    
    public function new(mml_ : String, buffer_ : Array<Float>, data_ : SiONData, channelCount_ : Int, resetEffector_ : Bool)
    {
        mml = mml_;
        buffer = buffer_;
        data = data_;
        if (data == null) data = new SiONData();
        channelCount = channelCount_;
        resetEffector = resetEffector_;
    }
}


