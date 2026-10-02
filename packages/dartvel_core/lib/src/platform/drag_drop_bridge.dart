/// The names the generated drag and drop bridges are reached by, shared by
/// the build that writes them and the runtime that calls them. One constant
/// each, because a class the build names one way and the runtime looks up
/// another is a lookup that answers nil, which is also the honest answer for
/// an application built with plain `flutter build`.
library;

/// The Android bridge: `dev.dartvel.jni.DartvelDragDrop`, as JNI names it.
const String dvAndroidDragDropClass = 'dev/dartvel/jni/DartvelDragDrop';

/// The iOS bridge's Objective-C class name, fixed with `@objc(...)` so Swift
/// does not mangle it.
const String dvIosDragDropClass = 'DartvelDragDrop';
