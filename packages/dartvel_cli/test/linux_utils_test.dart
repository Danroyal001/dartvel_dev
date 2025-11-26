import 'package:dartvel_cli/src/models/linux_dependency.dart';
import 'package:dartvel_cli/src/utils/linux_utils.dart';
import 'package:test/test.dart';

void main() {
  group('LinuxUtils', () {
    test('packageManagerLabel returns correct string', () {
      expect(packageManagerLabel(PackageManager.apt), 'apt');
      expect(packageManagerLabel(PackageManager.dnf), 'dnf');
    });

    test('buildInstallCommand generates correct command for apt', () {
      final cmd = buildInstallCommand(PackageManager.apt, ['pkg1', 'pkg2']);
      expect(cmd, containsAll(['apt-get', 'install', '-y', 'pkg1', 'pkg2']));
    });

    test('buildInstallCommand generates correct command for pacman', () {
      final cmd = buildInstallCommand(PackageManager.pacman, ['pkg1']);
      expect(cmd, containsAll(['pacman', '-Sy', '--noconfirm', 'pkg1']));
    });

    test('buildInstallCommand returns null for empty packages', () {
      final cmd = buildInstallCommand(PackageManager.apt, []);
      expect(cmd, isNull);
    });
  });
}
