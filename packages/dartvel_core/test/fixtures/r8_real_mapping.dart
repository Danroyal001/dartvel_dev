// Excerpts of a mapping.txt written by the R8 in Android SDK build-tools 36
// for a release build of a Dartvel app (Flutter 3.47.5, play-services and
// firebase-messaging 26.0.0 on the classpath), copied line for line, with the
// `residualsignature` comments left out. The expected frames in the tests that
// use it are what R8's own `retrace` tool printed for the same mapping and the
// same stack lines, so the retracer is held to R8's answer and not to this
// repository's idea of the format.
library;

const String r8RealMapping = r'''
com.google.android.gms.common.internal.BaseGmsClient -> R8$$REMOVED$$CLASS$$131:
# {"id":"sourceFile","fileName":"com.google.android.gms:play-services-basement@@18.9.0"}
com.google.android.gms.common.internal.ClientSettings -> t5:
# {"id":"sourceFile","fileName":"com.google.android.gms:play-services-base@@18.9.0"}
    java.util.Set zab -> a
com.google.android.gms.signin.internal.SignInClientImpl -> tx:
# {"id":"sourceFile","fileName":"com.google.android.gms:play-services-base@@18.9.0"}
    com.google.android.gms.common.internal.ClientSettings zac -> A
    boolean zab -> z
    5:14:android.os.IInterface createServiceInterface(android.os.IBinder):1:1 -> a
    15:19:android.os.IInterface createServiceInterface(android.os.IBinder):2:2 -> a
    20:23:void com.google.android.gms.signin.internal.zaf.<init>(android.os.IBinder):1:1 -> a
    20:23:android.os.IInterface createServiceInterface(android.os.IBinder):2 -> a
    1:6:java.lang.String com.google.android.gms.common.internal.ClientSettings.getRealClientPackageName():0:0 -> e
    1:6:android.os.Bundle getGetServiceRequestExtraArgs():1 -> e
      # {"id":"com.android.tools.r8.rewriteFrame","conditions":["throws(Ljava/lang/NullPointerException;)"],"actions":["removeInnerFrames(1)"]}
    7:8:android.content.Context com.google.android.gms.common.internal.BaseGmsClient.getContext():0:0 -> e
    7:8:android.os.Bundle getGetServiceRequestExtraArgs():2 -> e
    9:20:android.os.Bundle getGetServiceRequestExtraArgs():2:2 -> e
    21:24:java.lang.String com.google.android.gms.common.internal.ClientSettings.getRealClientPackageName():0:0 -> e
    21:24:android.os.Bundle getGetServiceRequestExtraArgs():3 -> e
    25:26:android.os.Bundle getGetServiceRequestExtraArgs():3:3 -> e
    27:30:android.os.Bundle getGetServiceRequestExtraArgs():4:4 -> e
com.google.android.gms.signin.internal.zaf -> g50:
# {"id":"sourceFile","fileName":"com.google.android.gms:play-services-base@@18.9.0"}
com.google.android.datatransport.runtime.scheduling.persistence.SQLiteEventStore$$ExternalSyntheticLambda0 -> dv:
# {"id":"sourceFile","fileName":"R8$$SyntheticClass"}
# {"id":"com.android.tools.r8.synthesized"}
    int SQLiteEventStore$$ExternalSyntheticLambda0.$r8$classId -> c
      # {"id":"com.android.tools.r8.synthesized"}
    1:10:void SQLiteEventStore$$ExternalSyntheticLambda0.<init>(SQLiteEventStore,AutoValue_TransportContext,int):0:0 -> <init>
      # {"id":"com.android.tools.r8.synthesized"}
    13:14:java.util.List com.google.android.datatransport.runtime.scheduling.persistence.SQLiteEventStore.lambda$loadBatch$8(com.google.android.datatransport.runtime.TransportContext,android.database.sqlite.SQLiteDatabase):354:354 -> apply
    13:14:java.lang.Object SQLiteEventStore$$ExternalSyntheticLambda0.apply(java.lang.Object):0 -> apply
    15:16:int com.google.android.datatransport.runtime.scheduling.persistence.AutoValue_EventStoreConfig.getLoadBatchSize():38:38 -> apply
    15:16:java.util.List com.google.android.datatransport.runtime.scheduling.persistence.SQLiteEventStore.lambda$loadBatch$8(com.google.android.datatransport.runtime.TransportContext,android.database.sqlite.SQLiteDatabase):354 -> apply
    15:16:java.lang.Object SQLiteEventStore$$ExternalSyntheticLambda0.apply(java.lang.Object):0 -> apply
com.google.android.datatransport.runtime.AutoProtoEncoderDoNotUseEncoder$ClientMetricsEncoder -> w1:
# {"id":"sourceFile","fileName":"AutoProtoEncoderDoNotUseEncoder.java"}
    1:2:void <clinit>():51:51 -> <clinit>
    1:2:void AutoProtoEncoderDoNotUseEncoder$ClientMetricsEncoder.<clinit>():0 -> <clinit>
      # {"id":"com.android.tools.r8.synthesized"}
    3:5:void <init>():50:50 -> <clinit>
    3:5:void <clinit>():51 -> <clinit>
    3:5:void AutoProtoEncoderDoNotUseEncoder$ClientMetricsEncoder.<clinit>():0 -> <clinit>
    22:25:void <clinit>():0:0 -> <clinit>
    22:25:void AutoProtoEncoderDoNotUseEncoder$ClientMetricsEncoder.<clinit>():0 -> <clinit>
kotlin.collections.ArraysKt___ArraysJvmKt -> kotlin.collections.ArraysKt___ArraysJvmKt:
    1:1:void calculateMaximumDisplayMetrics():5:5 -> a
''';
