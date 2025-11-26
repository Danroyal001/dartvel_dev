enum PackageManager { apt, dnf, yum, pacman, zypper, apk }

class LinuxDependency {
  final String binary;
  final String description;
  final Map<PackageManager, List<String>> packages;

  const LinuxDependency(
      {required this.binary,
      required this.description,
      required this.packages});

  List<String> packagesFor(PackageManager manager) =>
      packages[manager] ?? const <String>[];
}
