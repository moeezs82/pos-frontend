import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/backend_config.dart';
import '../config/license_public_key.dart';

class CounterIQLicense {
  final int version;
  final String product;
  final String customer;
  final String edition;
  final String deviceFingerprint;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final String signature;
  final String? signerThumbprint;

  const CounterIQLicense({
    required this.version,
    required this.product,
    required this.customer,
    required this.edition,
    required this.deviceFingerprint,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
    this.signerThumbprint,
  });

  factory CounterIQLicense.fromJson(Map<String, dynamic> json) {
    final version = int.tryParse(json['version']?.toString() ?? '');
    final product = json['product']?.toString().trim() ?? '';
    final customer = json['customer']?.toString().trim() ?? '';
    final edition = json['edition']?.toString().trim().toLowerCase() ?? '';
    final device = OfflineLicenseService.normalizeMachineCode(
      json['device_fingerprint']?.toString() ?? '',
    );
    final issuedAt = DateTime.tryParse(json['issued_at']?.toString() ?? '');
    final expiresRaw = json['expires_at']?.toString().trim() ?? '';
    final expiresAt = expiresRaw.isEmpty || expiresRaw == 'null'
        ? null
        : DateTime.tryParse(expiresRaw);
    final signature = json['signature']?.toString().trim() ?? '';

    if (version == null ||
        product.isEmpty ||
        customer.isEmpty ||
        edition.isEmpty ||
        device.length != 64 ||
        issuedAt == null ||
        (expiresRaw.isNotEmpty && expiresRaw != 'null' && expiresAt == null) ||
        signature.isEmpty) {
      throw const FormatException('The CounterIQ license file is incomplete or malformed.');
    }

    return CounterIQLicense(
      version: version,
      product: product,
      customer: customer,
      edition: edition,
      deviceFingerprint: device,
      issuedAt: issuedAt.toUtc(),
      expiresAt: expiresAt?.toUtc(),
      signature: signature,
      signerThumbprint: json['signer_thumbprint']?.toString().trim(),
    );
  }
}

class LicenseCheckResult {
  final bool isValid;
  final bool licenseExists;
  final String? message;
  final CounterIQLicense? license;

  const LicenseCheckResult._({
    required this.isValid,
    required this.licenseExists,
    this.message,
    this.license,
  });

  const LicenseCheckResult.valid(CounterIQLicense value)
      : this._(
          isValid: true,
          licenseExists: true,
          license: value,
        );

  const LicenseCheckResult.invalid({
    required bool licenseExists,
    required String message,
  }) : this._(
          isValid: false,
          licenseExists: licenseExists,
          message: message,
        );
}

/// Fully offline CounterIQ machine activation.
///
/// A customer machine never receives the private signing key. CounterIQ only
/// ships with the public X.509 certificate and verifies a `.ciqlic` file that
/// Application Owner signed on a separate trusted computer.
///
/// The machine fingerprint is generated from stable Windows hardware identity
/// values. A Windows MachineGuid is used only as a fallback when the machine
/// exposes too little usable hardware identity information.
class OfflineLicenseService {
  static const String _product = 'CounterIQ';
  static const int _licenseVersion = 1;
  static String get _licenseFileName => 'counteriq-${BackendConfig.mode}.ciqlic';

  const OfflineLicenseService._();

  static Future<LicenseCheckResult> checkInstalledLicense() async {
    if (!Platform.isWindows) {
      return const LicenseCheckResult.invalid(
        licenseExists: false,
        message: 'CounterIQ offline activation is supported on Windows only.',
      );
    }

    if (!LicensePublicKeyConfig.isConfigured) {
      return const LicenseCheckResult.invalid(
        licenseExists: false,
        message:
            'This CounterIQ build does not contain its offline licensing public key. '
            'Run the CounterIQ licensing setup before creating the customer build.',
      );
    }

    final file = await _installedLicenseFile();
    if (!await file.exists()) {
      return const LicenseCheckResult.invalid(
        licenseExists: false,
        message: 'This device has not been activated yet.',
      );
    }

    return verifyLicenseFile(file);
  }

  static Future<LicenseCheckResult> verifyLicenseFile(File file) async {
    try {
      if (!LicensePublicKeyConfig.isConfigured) {
        return const LicenseCheckResult.invalid(
          licenseExists: true,
          message: 'The CounterIQ licensing public key is not configured in this build.',
        );
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const LicenseCheckResult.invalid(
          licenseExists: true,
          message: 'The selected file is not a valid CounterIQ license.',
        );
      }

      final license = CounterIQLicense.fromJson(decoded);

      if (license.version != _licenseVersion || license.product != _product) {
        return const LicenseCheckResult.invalid(
          licenseExists: true,
          message: 'This license was not issued for this version of CounterIQ licensing.',
        );
      }

      if (license.edition != BackendConfig.mode) {
        return LicenseCheckResult.invalid(
          licenseExists: true,
          message:
              'This license is for the ${license.edition.toUpperCase()} edition, '
              'but this is a ${BackendConfig.mode.toUpperCase()} build.',
        );
      }

      final currentDevice = normalizeMachineCode(await machineCode());
      if (currentDevice != license.deviceFingerprint) {
        return const LicenseCheckResult.invalid(
          licenseExists: true,
          message:
              'This license belongs to a different computer. Send the machine code '
              'shown on this device to Application Owner for activation.',
        );
      }

      if (license.expiresAt != null && DateTime.now().toUtc().isAfter(license.expiresAt!)) {
        return LicenseCheckResult.invalid(
          licenseExists: true,
          message: 'This CounterIQ license expired on ${license.expiresAt!.toLocal()}.',
        );
      }

      final canonical = canonicalPayload(license);
      final signatureValid = await _verifySignature(
        payload: utf8.encode(canonical),
        signatureBase64: license.signature,
      );

      if (!signatureValid) {
        return const LicenseCheckResult.invalid(
          licenseExists: true,
          message:
              'The CounterIQ license signature is invalid. The license may have been '
              'changed, damaged, or issued by an unknown signer.',
        );
      }

      return LicenseCheckResult.valid(license);
    } on FormatException catch (error) {
      return LicenseCheckResult.invalid(
        licenseExists: true,
        message: error.message.toString(),
      );
    } on Object catch (error) {
      return LicenseCheckResult.invalid(
        licenseExists: true,
        message: 'CounterIQ could not validate the license. $error',
      );
    }
  }

  /// Validates [sourcePath] before copying it to CounterIQ's stable application
  /// support directory. A wrong-device, wrong-edition, expired or modified
  /// license is never installed.
  static Future<LicenseCheckResult> installLicenseFromPath(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return const LicenseCheckResult.invalid(
        licenseExists: false,
        message: 'The selected CounterIQ license file could not be found.',
      );
    }

    final check = await verifyLicenseFile(source);
    if (!check.isValid) return check;

    final destination = await _installedLicenseFile();
    await destination.parent.create(recursive: true);

    final bytes = await source.readAsBytes();
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);

    return check;
  }

  static Future<String> machineCode() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('CounterIQ machine codes are supported on Windows only.');
    }

    final powershell = await _resolvePowerShellExecutable();
    final result = await Process.run(
      powershell,
      const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _machineFingerprintPowerShell,
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      throw StateError(
        error.isEmpty
            ? 'Windows could not generate a CounterIQ machine identity.'
            : 'Windows could not generate a CounterIQ machine identity. $error',
      );
    }

    final fingerprint = normalizeMachineCode(result.stdout.toString());
    if (fingerprint.length != 64) {
      throw StateError('Windows returned an invalid CounterIQ machine identity.');
    }

    return _formatMachineCode(fingerprint);
  }

  static Future<String> _resolvePowerShellExecutable() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows PowerShell is available on Windows only.');
    }

    final roots = <String>{
      Platform.environment['SystemRoot']?.trim() ?? '',
      Platform.environment['WINDIR']?.trim() ?? '',
      r'C:\Windows',
    }..removeWhere((value) => value.isEmpty);

    final candidates = <String>[];
    for (final root in roots) {
      // Use an absolute path so installed CounterIQ does not depend on the
      // customer's PATH environment variable containing Windows PowerShell.
      candidates.add(
        p.windows.join(
          root,
          'System32',
          'WindowsPowerShell',
          'v1.0',
          'powershell.exe',
        ),
      );

      // Sysnative is useful if CounterIQ is ever built as a 32-bit process on
      // a 64-bit Windows installation. It does not exist for normal x64 builds.
      candidates.add(
        p.windows.join(
          root,
          'Sysnative',
          'WindowsPowerShell',
          'v1.0',
          'powershell.exe',
        ),
      );
    }

    final programFiles = <String>{
      Platform.environment['ProgramFiles']?.trim() ?? '',
      Platform.environment['ProgramW6432']?.trim() ?? '',
    }..removeWhere((value) => value.isEmpty);

    for (final root in programFiles) {
      candidates.add(
        p.windows.join(root, 'PowerShell', '7', 'pwsh.exe'),
      );
    }

    final checked = <String>{};
    for (final candidate in candidates) {
      final normalized = candidate.toLowerCase();
      if (!checked.add(normalized)) continue;
      if (await File(candidate).exists()) return candidate;
    }

    throw StateError(
      'CounterIQ could not find Windows PowerShell on this computer. '
      'Expected Windows PowerShell under the Windows System32 folder or '
      'PowerShell 7 under Program Files.',
    );
  }

  static String normalizeMachineCode(String value) =>
      value.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();

  static String _formatMachineCode(String fingerprint) {
    final normalized = normalizeMachineCode(fingerprint);
    final groups = <String>[];
    for (var index = 0; index < normalized.length; index += 8) {
      final end = index + 8 > normalized.length ? normalized.length : index + 8;
      groups.add(normalized.substring(index, end));
    }
    return groups.join('-');
  }

  /// Canonical representation signed by the Application Owner license generator.
  /// Do not change this without also changing generate_license.ps1 and bumping
  /// [_licenseVersion].
  static String canonicalPayload(CounterIQLicense license) {
    final customerBytes = utf8.encode(license.customer);
    final encodedCustomer = base64Url.encode(customerBytes).replaceAll('=', '');
    final issuedAt = _canonicalUtc(license.issuedAt);
    final expiresAt = license.expiresAt == null ? '' : _canonicalUtc(license.expiresAt!);

    return <String>[
      'version=${license.version}',
      'product=${license.product}',
      'customer=$encodedCustomer',
      'edition=${license.edition}',
      'device=${license.deviceFingerprint}',
      'issued_at=$issuedAt',
      'expires_at=$expiresAt',
    ].join('\n');
  }

  static String _canonicalUtc(DateTime value) {
    final utc = value.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static Future<File> _installedLicenseFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'licensing', _licenseFileName));
  }

  static Future<bool> _verifySignature({
    required List<int> payload,
    required String signatureBase64,
  }) async {
    late List<int> certificate;
    late List<int> signature;
    try {
      certificate = base64Decode(LicensePublicKeyConfig.certificateDerBase64);
      signature = base64Decode(signatureBase64);
    } on FormatException {
      return false;
    }

    final temp = await Directory.systemTemp.createTemp('counteriq-license-');
    try {
      final certificateFile = File(p.join(temp.path, 'public.cer'));
      final payloadFile = File(p.join(temp.path, 'payload.bin'));
      final signatureFile = File(p.join(temp.path, 'signature.bin'));
      final scriptFile = File(p.join(temp.path, 'verify.ps1'));

      await certificateFile.writeAsBytes(certificate, flush: true);
      await payloadFile.writeAsBytes(payload, flush: true);
      await signatureFile.writeAsBytes(signature, flush: true);
      await scriptFile.writeAsString(_signatureVerificationPowerShell, flush: true);

      final powershell = await _resolvePowerShellExecutable();
      final result = await Process.run(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
          '-CertificatePath',
          certificateFile.path,
          '-PayloadPath',
          payloadFile.path,
          '-SignaturePath',
          signatureFile.path,
        ],
        runInShell: false,
      );

      return result.exitCode == 0 && result.stdout.toString().trim() == 'VALID';
    } finally {
      try {
        await temp.delete(recursive: true);
      } on Object {
        // Temp cleanup failure must not affect a successful verification.
      }
    }
  }

  static const String _signatureVerificationPowerShell = r'''
param(
  [Parameter(Mandatory = $true)][string]$CertificatePath,
  [Parameter(Mandatory = $true)][string]$PayloadPath,
  [Parameter(Mandatory = $true)][string]$SignaturePath
)

$ErrorActionPreference = 'Stop'
try {
  $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
  if ($null -eq $rsa) { throw 'The CounterIQ licensing certificate does not contain an RSA public key.' }

  $payload = [System.IO.File]::ReadAllBytes($PayloadPath)
  $signature = [System.IO.File]::ReadAllBytes($SignaturePath)
  $valid = $rsa.VerifyData(
    $payload,
    $signature,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
  )

  if ($valid) {
    Write-Output 'VALID'
    exit 0
  }
  exit 3
} catch {
  Write-Error $_.Exception.Message
  exit 4
}
''';

  static const String _machineFingerprintPowerShell = r'''
$ErrorActionPreference = 'SilentlyContinue'

$hardware = New-Object System.Collections.Generic.List[string]
$fallback = New-Object System.Collections.Generic.List[string]

function Add-CounterIQPart {
  param(
    [System.Collections.Generic.List[string]]$Target,
    [string]$Name,
    [object]$Value
  )

  if ($null -eq $Value) { return }
  $text = $Value.ToString().Trim().ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($text)) { return }

  $invalid = @(
    'TO BE FILLED BY O.E.M.',
    'TO BE FILLED BY OEM',
    'DEFAULT STRING',
    'SYSTEM SERIAL NUMBER',
    'UNKNOWN',
    'NONE',
    'NOT SPECIFIED',
    'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF',
    '00000000-0000-0000-0000-000000000000'
  )
  if ($invalid -contains $text) { return }

  $Target.Add("$Name=$text")
}

try {
  $system = Get-CimInstance Win32_ComputerSystemProduct
  Add-CounterIQPart $hardware 'UUID' $system.UUID
} catch {
  try {
    $system = Get-WmiObject Win32_ComputerSystemProduct
    Add-CounterIQPart $hardware 'UUID' $system.UUID
  } catch {}
}

try {
  $bios = Get-CimInstance Win32_BIOS
  Add-CounterIQPart $hardware 'BIOS' $bios.SerialNumber
} catch {
  try {
    $bios = Get-WmiObject Win32_BIOS
    Add-CounterIQPart $hardware 'BIOS' $bios.SerialNumber
  } catch {}
}

try {
  $board = Get-CimInstance Win32_BaseBoard
  Add-CounterIQPart $hardware 'BOARD' $board.SerialNumber
} catch {
  try {
    $board = Get-WmiObject Win32_BaseBoard
    Add-CounterIQPart $hardware 'BOARD' $board.SerialNumber
  } catch {}
}

# Prefer hardware-only identity. MachineGuid is used only when Windows/OEM
# exposes fewer than two trustworthy hardware identifiers.
if ($hardware.Count -lt 2) {
  try {
    $machineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
    Add-CounterIQPart $fallback 'MACHINEGUID' $machineGuid
  } catch {}
}

$parts = @($hardware)
if ($hardware.Count -lt 2) { $parts += @($fallback) }
if ($parts.Count -eq 0) {
  Write-Error 'No stable Windows machine identifiers were available.'
  exit 2
}

$canonical = (($parts | Sort-Object) -join '|')
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
  $hash = $sha.ComputeHash($bytes)
  ([System.BitConverter]::ToString($hash)).Replace('-', '')
} finally {
  $sha.Dispose()
}
''';
}
