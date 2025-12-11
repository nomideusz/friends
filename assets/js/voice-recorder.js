/**
 * Voice Recording for Voice Notes
 * Uses MediaRecorder API with WebM/Opus format
 */

const MAX_DURATION_MS = 60000; // 60 seconds

export class VoiceRecorder {
  constructor() {
    this.mediaRecorder = null;
    this.audioChunks = [];
    this.startTime = null;
    this.durationMs = 0;
    this.onDataAvailable = null;
    this.onStop = null;
    this.timeoutId = null;
  }

  async start() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      this.audioChunks = [];
      this.startTime = Date.now();
      
      // Use WebM with Opus codec if available, fallback to default
      const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus")
        ? "audio/webm;codecs=opus"
        : "audio/webm";
      
      this.mediaRecorder = new MediaRecorder(stream, { mimeType });
      
      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          this.audioChunks.push(event.data);
        }
      };
      
      this.mediaRecorder.onstop = () => {
        this.durationMs = Date.now() - this.startTime;
        
        // Stop all tracks
        stream.getTracks().forEach(track => track.stop());
        
        const audioBlob = new Blob(this.audioChunks, { type: mimeType });
        
        if (this.onStop) {
          this.onStop(audioBlob, this.durationMs);
        }
      };
      
      this.mediaRecorder.start(100); // Collect data every 100ms
      
      // Auto-stop at max duration
      this.timeoutId = setTimeout(() => {
        if (this.mediaRecorder && this.mediaRecorder.state === "recording") {
          this.stop();
        }
      }, MAX_DURATION_MS);
      
      return true;
    } catch (error) {
      console.error("Failed to start recording:", error);
      return false;
    }
  }

  stop() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }
    
    if (this.mediaRecorder && this.mediaRecorder.state === "recording") {
      this.mediaRecorder.stop();
    }
  }

  getDuration() {
    if (this.startTime && this.mediaRecorder?.state === "recording") {
      return Date.now() - this.startTime;
    }
    return this.durationMs;
  }

  isRecording() {
    return this.mediaRecorder?.state === "recording";
  }
}

/**
 * Simple audio player for voice notes
 */
export class VoicePlayer {
  constructor(audioBlob, onProgress, onEnd) {
    this.audio = new Audio(URL.createObjectURL(audioBlob));
    this.onProgress = onProgress;
    this.onEnd = onEnd;
    
    this.audio.ontimeupdate = () => {
      if (this.onProgress) {
        const progress = (this.audio.currentTime / this.audio.duration) * 100;
        this.onProgress(progress);
      }
    };
    
    this.audio.onended = () => {
      if (this.onEnd) {
        this.onEnd();
      }
    };
  }

  play() {
    this.audio.play();
  }

  pause() {
    this.audio.pause();
  }

  toggle() {
    if (this.audio.paused) {
      this.play();
    } else {
      this.pause();
    }
  }

  seek(percent) {
    this.audio.currentTime = (percent / 100) * this.audio.duration;
  }

  destroy() {
    this.audio.pause();
    URL.revokeObjectURL(this.audio.src);
  }
}
