/// The Java classes `dartvel build android` writes for media, by their JNI
/// names.
///
/// One constant read by both halves -- the CLI that writes the class and the
/// Flutter runtime that looks it up -- because a name spelled twice is a
/// lookup that answers ClassNotFound for ever, which is also what an APK
/// built without media answers.
library;

const String dvAndroidMediaPlayerClass = 'dev/dartvel/jni/DartvelMediaPlayer';
const String dvAndroidMediaSessionClass = 'dev/dartvel/jni/DartvelMediaSession';
const String dvAndroidAudioFocusClass = 'dev/dartvel/jni/DartvelAudioFocus';
const String dvAndroidCameraClass = 'dev/dartvel/jni/DartvelCamera';
