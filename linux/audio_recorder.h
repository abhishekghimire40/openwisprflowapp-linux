#ifndef FLUTTER_PLUGIN_AUDIO_RECORDER_H_
#define FLUTTER_PLUGIN_AUDIO_RECORDER_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _AudioRecorder AudioRecorder;
typedef struct {
  GObjectClass parent_class;
} AudioRecorderClass;

FLUTTER_PLUGIN_EXPORT GType audio_recorder_get_type();

FLUTTER_PLUGIN_EXPORT void audio_recorder_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_AUDIO_RECORDER_H_
