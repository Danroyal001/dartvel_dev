import '../dartvel_client/dartvel_client.dart';

// docs:start storage-local
// The filesystem this process is standing on. On a server that is the
// server's disk; on a device it is the directory the application owns, which
// is what a file manager writes into. Same calls either way.
void storeOnDisk(String directory) {
  DV.FileStorage.configure(DVLocalFileStorageAdapter(root: directory));
}
// docs:end

// docs:start storage-s3
// A bucket is one more adapter behind the same calls. Swapping this line is
// the whole of moving from a disk to S3.
void configureStorage() {
  DV.FileStorage.configure(S3FileStorageAdapter(
    bucket: 'uploads',
    region: 'eu-west-1',
    credentials: DVAwsCredentials(
      accessKeyId: DV.Secrets.get('AWS_ACCESS_KEY_ID'),
      secretAccessKey: DV.Secrets.get('AWS_SECRET_ACCESS_KEY'),
    ),
  ));
}
// docs:end

Future<void> files(List<int> bytes) async {
  // docs:start storage-use
  await DV.FileStorage.put('avatars/ada.png', bytes, contentType: 'image/png');

  if (await DV.FileStorage.exists('avatars/ada.png')) {
    final List<int> image = await DV.FileStorage.get('avatars/ada.png');
    DV.log('${image.length} bytes');
  }

  final List<String> avatars = await DV.FileStorage.list(prefix: 'avatars/');
  await DV.FileStorage.delete('avatars/ada.png');
  // docs:end
  DV.log('$avatars');
}
