/// The Swift `dartvel build ios` compiles into the application so the iOS
/// `DV.Platform` bindings that need UIKit, delegates or completion blocks
/// have something to call.
///
/// Dart reaches the clipboard and haptics through `dart:ffi` straight to the
/// Objective-C runtime and C. The rest cannot go that way safely: the share
/// sheet, the camera and the pickers are view controllers presented on the
/// main thread; location, Bluetooth and the permission prompts answer through
/// delegates; LocalAuthentication and UserNotifications through blocks; and
/// `UIScreen.nativeBounds` returns a struct, which `objc_msgSend` from Dart
/// cannot receive without risking the stack. So the Swift does each in its
/// own terms and exports four C functions (`@_cdecl`) that Dart looks up in
/// the process. Answers come back as JSON through one C function pointer --
/// a `NativeCallable` on the Dart side. No platform channel anywhere.
///
/// Written for every iOS build and compiled into the Runner target, the same
/// way as the widget reload shim. An application built with plain `flutter
/// build ios` has none, and the bindings it backs stay unregistered with
/// `DVIosBindings.lastFailure` saying why.
library;

import 'package:dartvel_core/dartvel.dart'
    show
        dvIosPermissions,
        dvIosShimCallSymbol,
        dvIosShimCompletionSymbol,
        dvIosShimDiskFreeSymbol,
        dvIosShimNetworkEventId,
        dvIosShimOperations,
        dvIosShimVersion,
        dvIosShimVersionSymbol;

import 'apple_widget_reload.dart' show dvApplePbxprojWithRunnerSwift;

/// The file the shim is written to, inside `ios/Runner`.
const String dvIosPlatformShimFileName = 'DartvelPlatform.swift';

/// The prefix every pbxproj object this adds carries. Its own, so it is added
/// and removed independently of the widget reload shim.
const String dvIosPlatformShimIdPrefix = 'DA97E1DA97E3';

/// [pbxproj] with the shim compiled into the application target.
String dvIosPbxprojWithPlatformShim(String pbxproj) => dvApplePbxprojWithRunnerSwift(
      pbxproj,
      fileName: dvIosPlatformShimFileName,
      idPrefix: dvIosPlatformShimIdPrefix,
      include: true,
    );

/// The permission names a project asks for under `dartvel.ios.permissions`,
/// each with the sentence iOS shows in its prompt.
///
/// A list takes a default sentence per name; a map gives the project's own.
/// Declared rather than inferred: a key in Info.plist is a question App
/// Review asks about, and a framework that declared every one it could use
/// would put the address book on the listing of a torch application.
Map<String, String> dvIosRequestedPermissions(Object? dartvelSection) {
  final Object? ios = dartvelSection is Map ? dartvelSection['ios'] : null;
  final Object? listed = ios is Map ? ios['permissions'] : null;
  final Map<String, String> out = <String, String>{};
  if (listed is List) {
    for (final Object? entry in listed) {
      final String name = '$entry'.trim();
      if (name.isNotEmpty) out[name] = dvIosDefaultUsageSentence(name);
    }
  } else if (listed is Map) {
    for (final MapEntry<Object?, Object?> entry in listed.entries) {
      final String name = '${entry.key}'.trim();
      final String sentence = '${entry.value ?? ''}'.trim();
      if (name.isEmpty) continue;
      out[name] = sentence.isEmpty ? dvIosDefaultUsageSentence(name) : sentence;
    }
  }
  return out;
}

/// The names in [requested] Dartvel has no iOS permission for.
List<String> dvIosUnknownPermissions(Iterable<String> requested) =>
    <String>[for (final String name in requested) if (!dvIosPermissions.containsKey(name)) name];

/// The prompt sentence used when a project names a permission and no reason.
///
/// App Review rejects a vague one, so a project that ships should write its
/// own; this keeps a development build from being terminated on first ask.
String dvIosDefaultUsageSentence(String name) => switch (name) {
      'camera' => 'This app uses the camera to take photos.',
      'microphone' => 'This app uses the microphone to record audio.',
      'location' => 'This app uses your location while you are using it.',
      'contacts' => 'This app reads your contacts.',
      'photos' || 'media' => 'This app reads photos and videos from your library.',
      'bluetooth' => 'This app connects to Bluetooth devices.',
      'nfc' => 'This app reads NFC tags.',
      'biometrics' => 'This app uses Face ID to confirm it is you.',
      _ => 'This app uses $name.',
    };

/// The Info.plist entries [requested] needs, as key to plist value.
Map<String, String> dvIosUsageDescriptionEntries(Map<String, String> requested) {
  final Map<String, String> out = <String, String>{};
  for (final MapEntry<String, String> entry in requested.entries) {
    for (final String key in dvIosPermissions[entry.key]?.usageKeys ?? const <String>[]) {
      out.putIfAbsent(key, () => '<string>${_xml(entry.value)}</string>');
    }
  }
  return out;
}

const String _blockStart = '\t<!-- dartvel.ios.permissions: begin -->';
const String _blockEnd = '\t<!-- dartvel.ios.permissions: end -->';

/// [plist] with [entries] in a marked block in its top dictionary.
///
/// A key already present outside the block is the developer's: it is kept,
/// left out of the block, and named in [skipped]. With no entries the block
/// is removed, so taking a permission out of the pubspec takes the key out
/// of the app.
String dvWithIosPermissionsBlock(String plist, Map<String, String> entries, {List<String>? skipped}) {
  final RegExp block = RegExp('\n${RegExp.escape(_blockStart)}.*?${RegExp.escape(_blockEnd)}', dotAll: true);
  final String stripped = plist.replaceAll(block, '');
  final StringBuffer out = StringBuffer()..writeln(_blockStart);
  var wrote = false;
  for (final MapEntry<String, String> entry in entries.entries) {
    if (stripped.contains('<key>${entry.key}</key>')) {
      skipped?.add(entry.key);
      continue;
    }
    out
      ..writeln('\t<key>${entry.key}</key>')
      ..writeln('\t${entry.value}');
    wrote = true;
  }
  if (!wrote) return stripped;
  out.write(_blockEnd);
  final int close = stripped.lastIndexOf('</dict>');
  if (close < 0) return stripped;
  return '${stripped.substring(0, close)}$out\n${stripped.substring(close)}';
}

String _xml(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// The operations the generated Swift dispatches on, read back out of it.
///
/// For the test that holds the two halves together: every operation the Dart
/// sends must be a `case` here, or the phone answers "no operation".
Set<String> dvIosShimSourceOperations(String swift) => <String>{
      for (final RegExpMatch m in RegExp(r'^\s*case "([a-zA-Z.]+)":', multiLine: true).allMatches(swift)) m.group(1)!,
    };

/// The shim, as Swift.
String dvIosPlatformShimSource() {
  final String source = _swift
      .replaceAll(r'$VERSION_SYMBOL', dvIosShimVersionSymbol)
      .replaceAll(r'$COMPLETION_SYMBOL', dvIosShimCompletionSymbol)
      .replaceAll(r'$CALL_SYMBOL', dvIosShimCallSymbol)
      .replaceAll(r'$DISK_SYMBOL', dvIosShimDiskFreeSymbol)
      .replaceAll(r'$NETWORK_ID', '$dvIosShimNetworkEventId')
      // Last: it is a prefix of $VERSION_SYMBOL, which must go first.
      .replaceAll(r'$VERSION', '$dvIosShimVersion');
  assert(dvIosShimSourceOperations(source).containsAll(dvIosShimOperations));
  return source;
}

// Raw, so Swift's own `\(...)` interpolation passes through untouched. The
// few Dart values are `$NAME` placeholders replaced above.
const String _swift = r'''
// GENERATED by dartvel build ios. Do not edit: the next build writes it again.
//
// The iOS half of DV.Platform for everything Dart cannot reach through the
// Objective-C runtime directly: view controllers, delegates, completion
// blocks and struct returns. Dart calls the @_cdecl functions below through
// dart:ffi and is answered through one C function pointer. No platform
// channel is involved.
import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import CoreMotion
#if canImport(CoreNFC)
import CoreNFC
#endif
import Foundation
import LocalAuthentication
import MobileCoreServices
import Network
import Photos
import PhotosUI
import UIKit
import UserNotifications

public typealias DartvelCompletion = @convention(c) (Int64, UnsafeMutablePointer<CChar>?) -> Void

private var dartvelCompletion: DartvelCompletion?

@_cdecl("$VERSION_SYMBOL")
public func dartvelShimVersion() -> Int32 {
    return $VERSION
}

@_cdecl("$COMPLETION_SYMBOL")
public func dartvelSetCompletion(_ callback: DartvelCompletion?) {
    dartvelCompletion = callback
}

/// Copies both strings before returning, then does the work on the main
/// queue: UIKit and most of these frameworks require it, and async rather
/// than sync because the caller may already be on the main thread.
@_cdecl("$CALL_SYMBOL")
public func dartvelCall(_ id: Int64, _ op: UnsafePointer<CChar>?, _ json: UnsafePointer<CChar>?) {
    let name = op.map { String(cString: $0) } ?? ""
    let text = json.map { String(cString: $0) } ?? "{}"
    let args = ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:]
    DispatchQueue.main.async {
        DartvelPlatform.shared.handle(id: id, op: name, args: args)
    }
}

/// Synchronous, for the device runtime's health probe.
@_cdecl("$DISK_SYMBOL")
public func dartvelDiskFree(_ path: UnsafePointer<CChar>?) -> Int64 {
    guard let path = path else { return 0 }
    let url = URL(fileURLWithPath: String(cString: path))
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? 0
}

/// Hands [payload] to Dart as JSON. The string is strdup'd: Dart frees it.
func dartvelAnswer(_ id: Int64, _ payload: [String: Any]) {
    guard let callback = dartvelCompletion else { return }
    let data = (try? JSONSerialization.data(withJSONObject: payload))
        ?? Data("{\"error\":\"the answer could not be encoded\"}".utf8)
    callback(id, strdup(String(decoding: data, as: UTF8.self)))
}

func dartvelFail(_ id: Int64, _ message: String) {
    dartvelAnswer(id, ["error": message])
}

final class DartvelPlatform: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate,
    UNUserNotificationCenterDelegate {
    static let shared = DartvelPlatform()
    let contactStore = CNContactStore()

    func handle(id: Int64, op: String, args: [String: Any]) {
        switch op {
        case "share.text": shareText(id, args)
        case "screen.geometry": screenGeometry(id)
        case "permissions.status": permission(id, args, request: false)
        case "permissions.request": permission(id, args, request: true)
        case "camera.takePhoto": takePhoto(id)
        case "media.pick": pickMedia(id, args)
        case "contacts.list": listContacts(id, args)
        case "location.current": currentLocation(id, args)
        case "nfc.available": dartvelAnswer(id, ["available": nfcAvailable()])
        case "bluetooth.state": bluetoothState(id)
        case "bluetooth.scan": bluetoothScan(id, args)
        case "bluetooth.known": bluetoothKnown(id)
        case "sensors.sample": sensorSample(id, args)
        case "biometrics.can": biometricsCan(id)
        case "biometrics.authenticate": biometricsAuthenticate(id, args)
        case "notifications.send": sendNotification(id, args)
        case "kiosk.guidedAccess": guidedAccess(id, args)
        case "network.watch": watchNetwork(id)
        default: dartvelFail(id, "this shim has no operation \(op); rebuild with dartvel build ios")
        }
    }

    // MARK: - Shared

    /// Whether Info.plist carries every key in [keys]. iOS terminates an
    /// application that asks for a protected resource without its key, so
    /// this is read before anything is asked.
    func declared(_ keys: [String]) -> Bool {
        return keys.allSatisfy { Bundle.main.object(forInfoDictionaryKey: $0) != nil }
    }

    func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// A private copy in tmp, so the file outlives the picker's grant.
    func copyToTemporary(_ url: URL) -> URL? {
        let name = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dartvel-picked-\(UUID().uuidString)", isDirectory: true)
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    func item(_ url: URL) -> [String: Any] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ["path": url.path, "name": url.lastPathComponent, "mimeType": mimeType(url), "size": size]
    }

    func mimeType(_ url: URL) -> String {
        let ext = url.pathExtension as CFString
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil)?.takeRetainedValue(),
              let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() else {
            return ""
        }
        return mime as String
    }

    // MARK: - Share sheet and screen

    func shareText(_ id: Int64, _ args: [String: Any]) {
        guard let top = topViewController() else {
            return dartvelFail(id, "there is no window to present the share sheet from")
        }
        let sheet = UIActivityViewController(activityItems: [args["text"] as? String ?? ""], applicationActivities: nil)
        // An iPad presents it as a popover, which needs an anchor or UIKit
        // throws.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true) { dartvelAnswer(id, ["presented": true]) }
    }

    func screenGeometry(_ id: Int64) {
        let screen = UIScreen.main
        dartvelAnswer(id, [
            "width": Double(screen.nativeBounds.width),
            "height": Double(screen.nativeBounds.height),
            "scale": Double(screen.nativeScale),
        ])
    }

    // MARK: - Permissions

    func permission(_ id: Int64, _ args: [String: Any], request: Bool) {
        let name = args["permission"] as? String ?? ""
        let keys = args["keys"] as? [String] ?? []
        guard declared(keys) else {
            return dartvelAnswer(id, ["permission": name, "declared": false, "granted": false])
        }
        let reply: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                dartvelAnswer(id, ["permission": name, "declared": true, "granted": granted])
            }
        }
        switch name {
        case "camera", "microphone":
            let media: AVMediaType = name == "camera" ? .video : .audio
            let status = AVCaptureDevice.authorizationStatus(for: media)
            if status == .notDetermined && request {
                AVCaptureDevice.requestAccess(for: media, completionHandler: reply)
            } else {
                reply(status == .authorized)
            }
        case "location":
            let status = locationStatus()
            if status == .notDetermined && request {
                whenLocationAuthorized(reply)
            } else {
                reply(status == .authorizedWhenInUse || status == .authorizedAlways)
            }
        case "contacts":
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .notDetermined && request {
                self.contactStore.requestAccess(for: .contacts) { granted, _ in reply(granted) }
            } else {
                reply(contactsReadable(status))
            }
        case "photos", "media":
            if #available(iOS 14, *) {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .notDetermined && request {
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { answer in
                        reply(answer == .authorized || answer == .limited)
                    }
                } else {
                    reply(status == .authorized || status == .limited)
                }
            } else {
                let status = PHPhotoLibrary.authorizationStatus()
                if status == .notDetermined && request {
                    PHPhotoLibrary.requestAuthorization { answer in reply(answer == .authorized) }
                } else {
                    reply(status == .authorized)
                }
            }
        case "notifications":
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .notDetermined && request {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in reply(granted) }
                } else {
                    reply(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                }
            }
        case "bluetooth":
            if bluetoothAuthorization() == .notDetermined && request {
                // Creating the manager is what shows the prompt; the answer
                // arrives as a state update.
                stateWaiters.append { reply(self.bluetoothAuthorization() == .allowedAlways) }
                _ = central
            } else {
                reply(bluetoothAuthorization() == .allowedAlways)
            }
        case "nfc":
            reply(nfcAvailable())
        case "biometrics":
            var error: NSError?
            reply(LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
        default:
            dartvelFail(id, "iOS has no permission called \(name)")
        }
    }

    func contactsReadable(_ status: CNAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 18, *) { return status == .limited }
        return false
    }

    // MARK: - Camera and pickers

    var captureIds: [ObjectIdentifier: Int64] = [:]

    func takePhoto(_ id: Int64) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return dartvelFail(id, "this device has no camera")
        }
        guard declared(["NSCameraUsageDescription"]) else {
            return dartvelFail(id, "Info.plist does not declare NSCameraUsageDescription; add camera to dartvel.ios.permissions")
        }
        guard let top = topViewController() else {
            return dartvelFail(id, "there is no window to present the camera from")
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        captureIds[ObjectIdentifier(picker)] = id
        top.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let id = captureIds.removeValue(forKey: ObjectIdentifier(picker))
        picker.dismiss(animated: true)
        guard let id = id else { return }
        guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
            return dartvelFail(id, "the camera returned no image")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dartvel-photo-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            dartvelAnswer(id, ["items": [item(url)]])
        } catch {
            dartvelFail(id, "the photo could not be written: \(error)")
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        let id = captureIds.removeValue(forKey: ObjectIdentifier(picker))
        picker.dismiss(animated: true)
        if let id = id { dartvelAnswer(id, ["items": []]) }
    }

    func pickMedia(_ id: Int64, _ args: [String: Any]) {
        let type = args["type"] as? String ?? "any"
        let multiple = args["multiple"] as? Bool ?? false
        guard let top = topViewController() else {
            return dartvelFail(id, "there is no window to present the picker from")
        }
        if #available(iOS 14, *), type == "image" || type == "video" {
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = multiple ? 0 : 1
            configuration.filter = type == "image" ? .images : .videos
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            captureIds[ObjectIdentifier(picker)] = id
            top.present(picker, animated: true)
            return
        }
        let kinds = ["image": "public.image", "video": "public.movie", "audio": "public.audio"]
        let types = [kinds[type] ?? "public.item"]
        // In .import mode the picker hands over copies this app owns.
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.allowsMultipleSelection = multiple
        picker.delegate = self
        captureIds[ObjectIdentifier(picker)] = id
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = captureIds.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        let copies = urls.compactMap { copyToTemporary($0) }
        dartvelAnswer(id, ["items": copies.map { item($0) }])
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let id = captureIds.removeValue(forKey: ObjectIdentifier(controller)) {
            dartvelAnswer(id, ["items": []])
        }
    }

    // MARK: - Contacts

    func listContacts(_ id: Int64, _ args: [String: Any]) {
        guard declared(["NSContactsUsageDescription"]) else {
            return dartvelFail(id, "Info.plist does not declare NSContactsUsageDescription; add contacts to dartvel.ios.permissions")
        }
        let limit = args["limit"] as? Int ?? 0
        let fetch = {
            DispatchQueue.global(qos: .userInitiated).async {
                var people: [[String: Any]] = []
                let keys: [CNKeyDescriptor] = [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                ]
                let request = CNContactFetchRequest(keysToFetch: keys)
                request.sortOrder = .userDefault
                do {
                    try self.contactStore.enumerateContacts(with: request) { contact, stop in
                        people.append([
                            "id": contact.identifier,
                            "name": CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                            "phone": contact.phoneNumbers.first?.value.stringValue ?? "",
                        ])
                        if limit > 0 && people.count >= limit { stop.pointee = true }
                    }
                    DispatchQueue.main.async { dartvelAnswer(id, ["contacts": people]) }
                } catch {
                    DispatchQueue.main.async { dartvelFail(id, "the contacts query failed: \(error)") }
                }
            }
        }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            self.contactStore.requestAccess(for: .contacts) { granted, _ in
                if granted { fetch() } else {
                    DispatchQueue.main.async { dartvelFail(id, "the person did not grant contacts") }
                }
            }
        } else if contactsReadable(status) {
            fetch()
        } else {
            dartvelFail(id, "the person did not grant contacts")
        }
    }

    // MARK: - Location

    lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    var authorizationWaiters: [(Bool) -> Void] = []
    var locationWaiters: [Int64] = []

    func locationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14, *) { return locationManager.authorizationStatus }
        return CLLocationManager.authorizationStatus()
    }

    func whenLocationAuthorized(_ reply: @escaping (Bool) -> Void) {
        authorizationWaiters.append(reply)
        locationManager.requestWhenInUseAuthorization()
    }

    func authorizationChanged() {
        let status = locationStatus()
        if status == .notDetermined { return }
        let waiting = authorizationWaiters
        authorizationWaiters = []
        waiting.forEach { $0(status == .authorizedWhenInUse || status == .authorizedAlways) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationChanged() }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationChanged()
    }

    func locationMap(_ location: CLLocation) -> [String: Any] {
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "provider": "corelocation",
            "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000),
        ]
    }

    func currentLocation(_ id: Int64, _ args: [String: Any]) {
        guard declared(["NSLocationWhenInUseUsageDescription"]) else {
            return dartvelFail(id, "Info.plist does not declare NSLocationWhenInUseUsageDescription; add location to dartvel.ios.permissions")
        }
        let maxAge = (args["maxAgeSeconds"] as? NSNumber)?.doubleValue ?? 120
        let timeout = (args["timeoutSeconds"] as? NSNumber)?.doubleValue ?? 20
        if let last = locationManager.location, -last.timestamp.timeIntervalSinceNow <= maxAge {
            return dartvelAnswer(id, locationMap(last))
        }
        let start = {
            self.locationWaiters.append(id)
            self.locationManager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if let index = self.locationWaiters.firstIndex(of: id) {
                    self.locationWaiters.remove(at: index)
                    dartvelFail(id, "no position within \(Int(timeout)) seconds")
                }
            }
        }
        switch locationStatus() {
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        case .notDetermined:
            whenLocationAuthorized { granted in
                if granted { start() } else { dartvelFail(id, "the person did not grant location") }
            }
        default:
            dartvelFail(id, "the person did not grant location")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let waiting = locationWaiters
        locationWaiters = []
        waiting.forEach { dartvelAnswer($0, locationMap(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let waiting = locationWaiters
        locationWaiters = []
        waiting.forEach { dartvelFail($0, "Core Location failed: \(error.localizedDescription)") }
    }

    // MARK: - NFC

    /// Whether this device has a reader. No entitlement is needed to ask;
    /// reading a tag needs one, and is not bound.
    func nfcAvailable() -> Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    // MARK: - Bluetooth

    lazy var central: CBCentralManager = CBCentralManager(
        delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    var stateWaiters: [() -> Void] = []
    var seen: [UUID: CBPeripheral] = [:]
    var scanFound: [UUID: [String: Any]] = [:]

    func bluetoothAuthorization() -> CBManagerAuthorization {
        if #available(iOS 13.1, *) { return CBManager.authorization }
        return central.authorization
    }

    func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        default: return "unknown"
        }
    }

    /// Runs [then] once the manager has a state to report, or after three
    /// seconds of none.
    func withSettledState(_ then: @escaping () -> Void) {
        if central.state != .unknown && central.state != .resetting { return then() }
        var done = false
        let once = { if !done { done = true; then() } }
        stateWaiters.append(once)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: once)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let waiting = stateWaiters
        stateWaiters = []
        waiting.forEach { $0() }
    }

    func bluetoothDeclared(_ id: Int64) -> Bool {
        if declared(["NSBluetoothAlwaysUsageDescription"]) { return true }
        dartvelFail(id, "Info.plist does not declare NSBluetoothAlwaysUsageDescription; add bluetooth to dartvel.ios.permissions")
        return false
    }

    func bluetoothState(_ id: Int64) {
        guard bluetoothDeclared(id) else { return }
        withSettledState { dartvelAnswer(id, ["state": self.stateName(self.central.state)]) }
    }

    func bluetoothScan(_ id: Int64, _ args: [String: Any]) {
        guard bluetoothDeclared(id) else { return }
        let seconds = (args["seconds"] as? NSNumber)?.doubleValue ?? 4
        withSettledState {
            guard self.central.state == .poweredOn else {
                return dartvelFail(id, "Bluetooth is \(self.stateName(self.central.state))")
            }
            self.scanFound = [:]
            self.central.scanForPeripherals(withServices: nil, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                self.central.stopScan()
                dartvelAnswer(id, ["devices": Array(self.scanFound.values)])
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        seen[peripheral.identifier] = peripheral
        var device: [String: Any] = ["id": peripheral.identifier.uuidString, "rssi": RSSI.intValue]
        if let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            device["name"] = name
        }
        scanFound[peripheral.identifier] = device
    }

    /// What this process has seen. iOS keeps no list of paired devices an
    /// application may read.
    func bluetoothKnown(_ id: Int64) {
        guard bluetoothDeclared(id) else { return }
        dartvelAnswer(id, ["devices": seen.values.map { peripheral -> [String: Any] in
            var device: [String: Any] = [
                "id": peripheral.identifier.uuidString,
                "connected": peripheral.state == .connected,
            ]
            if let name = peripheral.name { device["name"] = name }
            return device
        }])
    }

    // MARK: - Motion

    let motion = CMMotionManager()

    func sensorSample(_ id: Int64, _ args: [String: Any]) {
        let sensor = args["sensor"] as? String ?? ""
        var answered = false
        let answer: (Double, Double, Double) -> Void = { x, y, z in
            if answered { return }
            answered = true
            dartvelAnswer(id, ["x": x, "y": y, "z": z])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !answered {
                answered = true
                dartvelFail(id, "no \(sensor) sample within two seconds")
            }
        }
        switch sensor {
        case "accelerometer":
            guard motion.isAccelerometerAvailable else { answered = true; return dartvelFail(id, "this device has no accelerometer") }
            motion.accelerometerUpdateInterval = 0.02
            motion.startAccelerometerUpdates(to: .main) { data, _ in
                guard let data = data else { return }
                self.motion.stopAccelerometerUpdates()
                answer(data.acceleration.x, data.acceleration.y, data.acceleration.z)
            }
        case "gyroscope":
            guard motion.isGyroAvailable else { answered = true; return dartvelFail(id, "this device has no gyroscope") }
            motion.gyroUpdateInterval = 0.02
            motion.startGyroUpdates(to: .main) { data, _ in
                guard let data = data else { return }
                self.motion.stopGyroUpdates()
                answer(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
            }
        default:
            answered = true
            dartvelFail(id, "no sensor called \(sensor)")
        }
    }

    // MARK: - LocalAuthentication

    func biometricsCan(_ id: Int64) {
        var error: NSError?
        let available = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        dartvelAnswer(id, ["available": available])
    }

    func biometricsAuthenticate(_ id: Int64, _ args: [String: Any]) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return dartvelAnswer(id, ["authenticated": false, "reason": error?.localizedDescription ?? "unavailable"])
        }
        if context.biometryType == .faceID && !declared(["NSFaceIDUsageDescription"]) {
            return dartvelFail(id, "Info.plist does not declare NSFaceIDUsageDescription; add biometrics to dartvel.ios.permissions")
        }
        let reason = args["reason"] as? String ?? "Confirm it is you"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { dartvelAnswer(id, ["authenticated": ok]) }
        }
    }

    // MARK: - Notifications

    func sendNotification(_ id: Int64, _ args: [String: Any]) {
        let center = UNUserNotificationCenter.current()
        // Without a delegate iOS drops a notification posted while the app
        // is in front, which is exactly when somebody is testing it.
        if center.delegate == nil { center.delegate = self }
        let post = {
            let content = UNMutableNotificationContent()
            content.title = args["title"] as? String ?? ""
            content.body = args["body"] as? String ?? ""
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                DispatchQueue.main.async { dartvelAnswer(id, ["delivered": error == nil]) }
            }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { post() } else {
                        DispatchQueue.main.async { dartvelAnswer(id, ["delivered": false]) }
                    }
                }
            default:
                DispatchQueue.main.async { dartvelAnswer(id, ["delivered": false]) }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    // MARK: - Guided Access

    func guidedAccess(_ id: Int64, _ args: [String: Any]) {
        let enabled = args["enabled"] as? Bool ?? false
        UIAccessibility.requestGuidedAccessSession(enabled: enabled) { success in
            DispatchQueue.main.async {
                dartvelAnswer(id, ["enabled": enabled ? success : UIAccessibility.isGuidedAccessEnabled])
            }
        }
    }

    // MARK: - Network

    var pathMonitor: NWPathMonitor?

    func watchNetwork(_ id: Int64) {
        if pathMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let status: String
                switch path.status {
                case .satisfied: status = "satisfied"
                case .requiresConnection: status = "requiresConnection"
                default: status = "unsatisfied"
                }
                dartvelAnswer($NETWORK_ID, [
                    "status": status,
                    "expensive": path.isExpensive,
                    "constrained": path.isConstrained,
                ])
            }
            monitor.start(queue: DispatchQueue(label: "dev.dartvel.network"))
            pathMonitor = monitor
        }
        dartvelAnswer(id, ["watching": true])
    }
}

@available(iOS 14, *)
extension DartvelPlatform: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let id = captureIds.removeValue(forKey: ObjectIdentifier(picker))
        picker.dismiss(animated: true)
        guard let id = id else { return }
        let group = DispatchGroup()
        var items: [[String: Any]] = []
        let lock = NSLock()
        for result in results {
            let provider = result.itemProvider
            let identifier = provider.hasItemConformingToTypeIdentifier("public.movie") ? "public.movie" : "public.image"
            group.enter()
            // The file is deleted when this returns, so it is copied inside.
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                if let url = url, let copy = self.copyToTemporary(url) {
                    let entry = self.item(copy)
                    lock.lock(); items.append(entry); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { dartvelAnswer(id, ["items": items]) }
    }
}
''';
