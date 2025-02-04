#include "audio_recorder.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <alsa/asoundlib.h>
#include <sys/stat.h>
#include <unistd.h>

#define AUDIO_RECORDER(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), audio_recorder_get_type(), \
                             AudioRecorder))

struct _AudioRecorder {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  snd_pcm_t* capture_handle;
  bool is_recording;
  char* output_path;
  GThread* record_thread;
  GMutex mutex;
  GCond cond;
};

G_DEFINE_TYPE(AudioRecorder, audio_recorder, g_object_get_type())

// WAV header structure
struct WavHeader {
  // RIFF chunk
  char riff_header[4] = {'R', 'I', 'F', 'F'};
  uint32_t wav_size = 0;        // Will be filled later
  char wave_header[4] = {'W', 'A', 'V', 'E'};
  
  // fmt sub-chunk
  char fmt_header[4] = {'f', 'm', 't', ' '};
  uint32_t fmt_chunk_size = 16;
  uint16_t audio_format = 1;     // PCM
  uint16_t num_channels = 1;     // Mono
  uint32_t sample_rate = 16000;
  uint32_t byte_rate = 32000;    // sample_rate * num_channels * bits_per_sample/8
  uint16_t block_align = 2;      // num_channels * bits_per_sample/8
  uint16_t bits_per_sample = 16;
  
  // data sub-chunk
  char data_header[4] = {'d', 'a', 't', 'a'};
  uint32_t data_chunk_size = 0;  // Will be filled later
};

static gpointer record_thread_func(gpointer data) {
  AudioRecorder* recorder = AUDIO_RECORDER(data);
  FILE* output_file = fopen(recorder->output_path, "wb");
  if (!output_file) {
    g_mutex_lock(&recorder->mutex);
    recorder->is_recording = false;
    g_mutex_unlock(&recorder->mutex);
    return nullptr;
  }

  // Write WAV header
  WavHeader header;
  fwrite(&header, sizeof(header), 1, output_file);
  
  const int buffer_frames = 1024;
  int16_t buffer[buffer_frames];
  size_t total_bytes = 0;

  g_mutex_lock(&recorder->mutex);
  while (recorder->is_recording) {
    g_mutex_unlock(&recorder->mutex);
    
    int frames = snd_pcm_readi(recorder->capture_handle, buffer, buffer_frames);
    if (frames > 0) {
      size_t bytes_written = fwrite(buffer, sizeof(int16_t), frames, output_file);
      total_bytes += bytes_written * sizeof(int16_t);
    } else if (frames < 0) {
      frames = snd_pcm_recover(recorder->capture_handle, frames, 0);
      if (frames < 0) {
        g_mutex_lock(&recorder->mutex);
        recorder->is_recording = false;
        g_mutex_unlock(&recorder->mutex);
        break;
      }
    }
    
    g_mutex_lock(&recorder->mutex);
  }
  g_mutex_unlock(&recorder->mutex);

  // Update WAV header with final sizes
  fseek(output_file, 0, SEEK_SET);
  header.wav_size = total_bytes + sizeof(WavHeader) - 8;
  header.data_chunk_size = total_bytes;
  fwrite(&header, sizeof(header), 1, output_file);
  
  fclose(output_file);
  return nullptr;
}

static FlMethodResponse* start_recording(AudioRecorder* self,
                                      FlValue* args) {
  if (self->is_recording) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "already_recording", "Recording is already in progress", nullptr));
  }

  const char* file_path = fl_value_get_string(
      fl_value_lookup_string(args, "path"));
  
  int err;
  if ((err = snd_pcm_open(&self->capture_handle, "default",
                         SND_PCM_STREAM_CAPTURE, 0)) < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "init_failed",
        "Failed to open audio device",
        fl_value_new_string(snd_strerror(err))));
  }

  snd_pcm_hw_params_t* hw_params;
  snd_pcm_hw_params_alloca(&hw_params);
  snd_pcm_hw_params_any(self->capture_handle, hw_params);
  snd_pcm_hw_params_set_access(self->capture_handle, hw_params,
                              SND_PCM_ACCESS_RW_INTERLEAVED);
  snd_pcm_hw_params_set_format(self->capture_handle, hw_params,
                              SND_PCM_FORMAT_S16_LE);
  unsigned int rate = 16000;
  snd_pcm_hw_params_set_rate_near(self->capture_handle, hw_params,
                                 &rate, nullptr);
  snd_pcm_hw_params_set_channels(self->capture_handle, hw_params, 1);
  
  if ((err = snd_pcm_hw_params(self->capture_handle, hw_params)) < 0) {
    snd_pcm_close(self->capture_handle);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "init_failed",
        "Failed to set hardware parameters",
        fl_value_new_string(snd_strerror(err))));
  }

  g_mutex_lock(&self->mutex);
  self->output_path = strdup(file_path);
  self->is_recording = true;
  g_mutex_unlock(&self->mutex);

  // Start recording in a new thread
  self->record_thread = g_thread_new("record_thread", record_thread_func, self);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* stop_recording(AudioRecorder* self) {
  if (!self->is_recording) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "not_recording", "No recording in progress", nullptr));
  }

  g_mutex_lock(&self->mutex);
  self->is_recording = false;
  g_mutex_unlock(&self->mutex);

  if (self->record_thread) {
    g_thread_join(self->record_thread);
    self->record_thread = nullptr;
  }

  snd_pcm_close(self->capture_handle);
  free(self->output_path);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel* channel,
                          FlMethodCall* method_call,
                          gpointer user_data) {
  AudioRecorder* self = AUDIO_RECORDER(user_data);

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "startRecording") == 0) {
    response = start_recording(self, args);
  } else if (strcmp(method, "stopRecording") == 0) {
    response = stop_recording(self);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void audio_recorder_dispose(GObject* object) {
  AudioRecorder* self = AUDIO_RECORDER(object);
  if (self->is_recording) {
    stop_recording(self);
  }
  g_mutex_clear(&self->mutex);
  g_cond_clear(&self->cond);
  G_OBJECT_CLASS(audio_recorder_parent_class)->dispose(object);
}

static void audio_recorder_class_init(AudioRecorderClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = audio_recorder_dispose;
}

static void audio_recorder_init(AudioRecorder* self) {
  self->is_recording = false;
  self->output_path = nullptr;
  self->record_thread = nullptr;
  g_mutex_init(&self->mutex);
  g_cond_init(&self->cond);
}

void audio_recorder_register_with_registrar(FlPluginRegistrar* registrar) {
  AudioRecorder* plugin = AUDIO_RECORDER(
      g_object_new(audio_recorder_get_type(), nullptr));
  plugin->registrar = registrar;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "audio_recorder",
                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                          g_object_ref(plugin),
                                          g_object_unref);
  g_object_unref(plugin);
}
