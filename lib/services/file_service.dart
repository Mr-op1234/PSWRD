import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';

class FileService {
  static const String ASCII_MAP_FILE = "AsciiMap.csv";
  static const String VALUE_MAP_FILE = "ValueMap.csv";
  static const String APP_FOLDER_NAME = "PSWRD_Secure_Data";
  static const String EXPORT_ZIP_NAME = "PSWRD_Files.zip";
  
  // Will be set dynamically based on device capabilities
  static String APP_DATA_DIR = "";
  static String PUBLIC_EXPORT_DIR = "";
  
  static Map<int, String> asciiMap = {};
  static Map<int, String> valueMap = {};
  
  static Future<bool> initializeFiles() async {
    try {
      // Get the appropriate directory path
      await setupAppDirectory();
      
      print("Using directory: $APP_DATA_DIR");
      
      // Create directory if it doesn't exist
      Directory directory = Directory(APP_DATA_DIR);
      if (!await directory.exists()) {
        try {
          await directory.create(recursive: true);
          print("Created directory: $APP_DATA_DIR");
        } catch (e) {
          print("Error creating directory: $e");
          throw Exception("Failed to create directory: $e");
        }
      }
      
      // For Windows, special handling for directory issues
      if (Platform.isWindows) {
        try {
          // Test write permissions
          final testFile = File('$APP_DATA_DIR/test_write.txt');
          await testFile.writeAsString('Test write access');
          await testFile.delete();
          print("Directory is writable on Windows");
        } catch (e) {
          print("Windows write permission error: $e");
          throw Exception("Cannot write to Windows directory $APP_DATA_DIR. Please run the app with administrator privileges.");
        }
      }
      
      // Verify directory is writable by trying to create a test file
      try {
        final testFile = File('$APP_DATA_DIR/test_write.txt');
        await testFile.writeAsString('Test write access');
        await testFile.delete();
        print("Directory is writable");
      } catch (e) {
        print("Directory is not writable: $e");
        throw Exception("Directory is not writable: $e");
      }
      
      // Initialize ASCII map file
      try {
        if (!await File('$APP_DATA_DIR/$ASCII_MAP_FILE').exists()) {
          await createAsciiMap();
        } else {
          await loadAsciiMap();
        }
      } catch (e) {
        print("Error with ASCII map file: $e");
        // Try to recreate the file
        try {
          print("Attempting to recreate ASCII map file");
          await createAsciiMap();
        } catch (e2) {
          print("Failed to recover ASCII map: $e2");
          throw Exception("Failed to initialize ASCII map file: $e2");
        }
      }
      
      // Initialize Value map file
      try {
        if (!await File('$APP_DATA_DIR/$VALUE_MAP_FILE').exists()) {
          await createValueMap();
        } else {
          await loadValueMap();
        }
      } catch (e) {
        print("Error with Value map file: $e");
        // Try to recreate the file
        try {
          print("Attempting to recreate Value map file");
          await createValueMap();
        } catch (e2) {
          print("Failed to recover Value map: $e2");
          throw Exception("Failed to initialize Value map file: $e2");
        }
      }
      
      // Validate that maps were loaded properly
      if (asciiMap.isEmpty || valueMap.isEmpty) {
        throw Exception("Maps failed to load properly");
      }
      
      print("ASCII Map size: ${asciiMap.length}, Value Map size: ${valueMap.length}");
      
      // Return true to indicate success
      return true;
    } catch (e) {
      print("Error in initializeFiles: $e");
      // Return false to indicate failure
      return false;
    }
  }
  
  // Set up the app directory using only private app storage
  static Future<void> setupAppDirectory() async {
    try {
      if (Platform.isWindows) {
        // Use the specific Windows directory requested
        APP_DATA_DIR = "C:\\ProgramData\\PSWRD\\App Data\\Core Files";
        
        // For exports on Windows, use the Downloads folder
        final String userHome = Platform.environment['USERPROFILE'] ?? '';
        PUBLIC_EXPORT_DIR = "$userHome\\Downloads";
      } else {
        // For Android and other platforms, use app's private directory
        final appDir = await getApplicationDocumentsDirectory();
        APP_DATA_DIR = "${appDir.path}/$APP_FOLDER_NAME";
        
        // For exports based on platform
        if (Platform.isAndroid) {
          PUBLIC_EXPORT_DIR = "/storage/emulated/0/Download";
        } else {
          // Default to app documents directory for other platforms
          PUBLIC_EXPORT_DIR = appDir.path;
        }
      }
      
      print("Final storage path: $APP_DATA_DIR");
      print("Public export path: $PUBLIC_EXPORT_DIR");
    } catch (e) {
      print("Error setting up directory: $e");
      throw Exception("Failed to access application directory: $e");
    }
  }
  
  static Future<void> createAsciiMap() async {
    try {
      Map<int, String> map = {};
      
      // Create random ASCII values for numbers and letters
      List<int> asciiNum = List.generate(10, (i) => i + 48)..shuffle();
      List<int> asciiLetters = List.generate(26, (i) => i + 97)..shuffle();
      List<int> asciiValues = [...asciiNum, ...asciiLetters];
      List<int> asciiIndices = [...asciiValues];
      
      asciiValues.shuffle();
      asciiIndices.shuffle();
      
      // Create mapping
      for (int i = 0; i < asciiIndices.length; i++) {
        map[asciiIndices[i]] = String.fromCharCode(asciiValues[i]);
      }
      
      // Save map to CSV
      List<List<dynamic>> rows = [
        ["Key", "Value"]
      ];
      
      map.forEach((key, value) {
        rows.add([key, value]);
      });
      
      String csv = const ListToCsvConverter().convert(rows);
      final File file = File('$APP_DATA_DIR/$ASCII_MAP_FILE');
      await file.writeAsString(csv);
      
      // Ensure the map is populated
      if (map.isEmpty) {
        throw Exception("Failed to create ASCII map");
      }
      
      asciiMap = Map<int, String>.from(map);
      print("Created ASCII map with ${asciiMap.length} entries");
    } catch (e) {
      print("Error creating ASCII map: $e");
      throw Exception("Failed to create ASCII map: $e");
    }
  }
  
  static Future<void> createValueMap() async {
    try {
      Map<int, String> map = {};
      
      // Create values from 0 to 35
      List<int> values = List.generate(36, (i) => i);
      
      // Create random characters for numbers and letters
      List<int> numVal = List.generate(10, (i) => i + 48)..shuffle();
      List<String> numChars = numVal.map((e) => String.fromCharCode(e)).toList();
      
      List<int> letterVal = List.generate(26, (i) => i + 97)..shuffle();
      List<String> letterChars = letterVal.map((e) => String.fromCharCode(e)).toList();
      
      List<String> totalPuzzles = [...numChars, ...letterChars]..shuffle();
      
      // Create mapping
      for (int i = 0; i < values.length; i++) {
        map[i] = totalPuzzles[i];
      }
      
      // Save map to CSV
      List<List<dynamic>> rows = [
        ["Key", "Value"]
      ];
      
      map.forEach((key, value) {
        rows.add([key, value]);
      });
      
      String csv = const ListToCsvConverter().convert(rows);
      final File file = File('$APP_DATA_DIR/$VALUE_MAP_FILE');
      await file.writeAsString(csv);
      
      // Ensure the map is populated
      if (map.isEmpty) {
        throw Exception("Failed to create value map");
      }
      
      valueMap = Map<int, String>.from(map);
      print("Created value map with ${valueMap.length} entries");
    } catch (e) {
      print("Error creating value map: $e");
      throw Exception("Failed to create value map: $e");
    }
  }
  
  static Future<void> loadAsciiMap() async {
    try {
      final File file = File('$APP_DATA_DIR/$ASCII_MAP_FILE');
      final String contents = await file.readAsString();
      
      List<List<dynamic>> rows = const CsvToListConverter().convert(contents);
      
      // Skip header row
      Map<int, String> map = {};
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length >= 2) {
          int key = int.parse(rows[i][0].toString());
          String value = rows[i][1].toString();
          map[key] = value;
        }
      }
      
      // Ensure the map is populated
      if (map.isEmpty) {
        throw Exception("No data found in ASCII map file");
      }
      
      asciiMap = map;
      print("Loaded ASCII map with ${asciiMap.length} entries");
    } catch (e) {
      print("Error loading ASCII map: $e");
      throw Exception("Failed to load ASCII map: $e");
    }
  }
  
  static Future<void> loadValueMap() async {
    try {
      final File file = File('$APP_DATA_DIR/$VALUE_MAP_FILE');
      final String contents = await file.readAsString();
      
      List<List<dynamic>> rows = const CsvToListConverter().convert(contents);
      
      // Skip header row
      Map<int, String> map = {};
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length >= 2) {
          int key = int.parse(rows[i][0].toString());
          String value = rows[i][1].toString();
          map[key] = value;
        }
      }
      
      // Ensure the map is populated
      if (map.isEmpty) {
        throw Exception("No data found in value map file");
      }
      
      valueMap = map;
      print("Loaded value map with ${valueMap.length} entries");
    } catch (e) {
      print("Error loading value map: $e");
      throw Exception("Failed to load value map: $e");
    }
  }
  
  static String generateRandomKey(int length) {
    final Random random = Random();
    const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  // Get the current storage path
  static String getCurrentStoragePath() {
    return APP_DATA_DIR;
  }

  // ==================== NEW FUNCTIONS ====================
  
  // Export files as ZIP to Download directory
  static Future<String?> exportFilesToZip() async {
    try {
      Fluttertoast.cancel(); // Cancel any existing toasts
      
      // Only check permissions on Android
      if (Platform.isAndroid) {
        // First check if we already have the permission before requesting
        final sdkVersion = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        bool hasPermission = false;
        
        if (sdkVersion >= 33) {
          // For Android 13+, we need photo/media permissions
          print("Using photo/media permissions for Android 13+");
          final photosStatus = await Permission.photos.status;
          print("Photos permission status: $photosStatus");
          
          if (photosStatus.isGranted) {
            hasPermission = true;
          } else {
            final requestStatus = await Permission.photos.request();
            print("Photos permission request result: $requestStatus");
            hasPermission = requestStatus.isGranted;
          }
        } else {
          // For older Android versions, use storage permission
          final status = await Permission.storage.status;
          print("Storage permission status: $status");
          
          if (status.isGranted) {
            hasPermission = true;
          } else {
            final requestStatus = await Permission.storage.request();
            print("Storage permission request result: $requestStatus");
            hasPermission = requestStatus.isGranted;
          }
        }
        
        if (!hasPermission) {
          Fluttertoast.showToast(
            msg: 'Storage permission is required for export operations',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.red,
          );
          return null;
        }
      }
      
      // Create temp directory for ZIP creation
      final tempDir = await getTemporaryDirectory();
      final tempPath = "${tempDir.path}/temp_export";
      
      final tempDirObj = Directory(tempPath);
      if (await tempDirObj.exists()) {
        await tempDirObj.delete(recursive: true);
      }
      await tempDirObj.create(recursive: true);
      
      // Copy files to temp dir
      final asciiSource = File('$APP_DATA_DIR/$ASCII_MAP_FILE');
      final valueSource = File('$APP_DATA_DIR/$VALUE_MAP_FILE');
      
      final asciiTempDest = File('$tempPath/$ASCII_MAP_FILE');
      final valueTempDest = File('$tempPath/$VALUE_MAP_FILE');
      
      if (await asciiSource.exists()) {
        await asciiSource.copy(asciiTempDest.path);
      } else {
        throw Exception("ASCII map file not found for export");
      }
      
      if (await valueSource.exists()) {
        await valueSource.copy(valueTempDest.path);
      } else {
        throw Exception("Value map file not found for export");
      }
      
      // Create ZIP file
      final zipFileName = Platform.isWindows ? EXPORT_ZIP_NAME.replaceAll('/', '\\') : EXPORT_ZIP_NAME;
      final zipFilePath = "$PUBLIC_EXPORT_DIR/$zipFileName";
      print("Exporting to zip file path: $zipFilePath");
      
      final encoder = ZipFileEncoder();
      try {
        encoder.create(zipFilePath);
        await encoder.addDirectory(Directory(tempPath));
        encoder.close();
        
        print("ZIP file created successfully at: $zipFilePath");
      } catch (e) {
        print("Error creating ZIP: $e");
        throw Exception("Failed to create ZIP file: $e");
      }
      
      // Clean up temp directory
      await tempDirObj.delete(recursive: true);
      
      return zipFilePath;
    } catch (e) {
      print("Error exporting files: $e");
      return null;
    }
  }
  
  // Import ASCII Map file from external source
  static Future<bool> importAsciiMapFile(String filePath) async {
    try {
      // Ensure directory exists first
      await setupAppDirectory();
      
      Directory directory = Directory(APP_DATA_DIR);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print("Created directory for import: $APP_DATA_DIR");
      }
      
      // Read the file
      final File importFile = File(filePath);
      if (!await importFile.exists()) {
        throw Exception("Import file not found");
      }
      
      final String contents = await importFile.readAsString();
      
      // Validate CSV structure
      List<List<dynamic>> rows = const CsvToListConverter().convert(contents);
      
      // Basic validation:
      // 1. Must have at least header row + data rows
      if (rows.length < 2) {
        throw Exception("Invalid CSV: insufficient data");
      }
      
      // 2. Check header row
      if (rows[0].length < 2 || 
          rows[0][0].toString().toLowerCase() != "key" || 
          rows[0][1].toString().toLowerCase() != "value") {
        throw Exception("Invalid CSV: header must contain 'Key' and 'Value' columns");
      }
      
      // 3. Validate data format
      Map<int, String> testMap = {};
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length < 2) {
          throw Exception("Invalid CSV: row $i has insufficient columns");
        }
        
        try {
          int key = int.parse(rows[i][0].toString());
          String value = rows[i][1].toString();
          if (value.isEmpty) {
            throw Exception("Invalid CSV: empty value at row $i");
          }
          testMap[key] = value;
        } catch (e) {
          throw Exception("Invalid CSV format at row $i: $e");
        }
      }
      
      // 4. Verify we have the expected number of entries
      if (testMap.length < 30) { // Expecting at least 36 entries (0-9 + a-z)
        throw Exception("Invalid ASCII map: insufficient entries (found ${testMap.length}, expected at least 30)");
      }
      
      // All validations passed, save the file
      final File destFile = File('$APP_DATA_DIR/$ASCII_MAP_FILE');
      await importFile.copy(destFile.path);
      
      // Reload the map
      await loadAsciiMap();
      
      return true;
    } catch (e) {
      print("Error importing ASCII map: $e");
      return false;
    }
  }
  
  // Import Value Map file from external source
  static Future<bool> importValueMapFile(String filePath) async {
    try {
      // Ensure directory exists first
      await setupAppDirectory();
      
      Directory directory = Directory(APP_DATA_DIR);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print("Created directory for import: $APP_DATA_DIR");
      }
      
      // Read the file
      final File importFile = File(filePath);
      if (!await importFile.exists()) {
        throw Exception("Import file not found");
      }
      
      final String contents = await importFile.readAsString();
      
      // Validate CSV structure
      List<List<dynamic>> rows = const CsvToListConverter().convert(contents);
      
      // Basic validation:
      // 1. Must have at least header row + data rows
      if (rows.length < 2) {
        throw Exception("Invalid CSV: insufficient data");
      }
      
      // 2. Check header row
      if (rows[0].length < 2 || 
          rows[0][0].toString().toLowerCase() != "key" || 
          rows[0][1].toString().toLowerCase() != "value") {
        throw Exception("Invalid CSV: header must contain 'Key' and 'Value' columns");
      }
      
      // 3. Validate data format
      Map<int, String> testMap = {};
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length < 2) {
          throw Exception("Invalid CSV: row $i has insufficient columns");
        }
        
        try {
          int key = int.parse(rows[i][0].toString());
          String value = rows[i][1].toString();
          if (value.isEmpty) {
            throw Exception("Invalid CSV: empty value at row $i");
          }
          testMap[key] = value;
        } catch (e) {
          throw Exception("Invalid CSV format at row $i: $e");
        }
      }
      
      // 4. Verify we have the expected number of entries
      if (testMap.length < 30) { // Expecting at least 36 entries (0-9 + a-z)
        throw Exception("Invalid value map: insufficient entries (found ${testMap.length}, expected at least 30)");
      }
      
      // All validations passed, save the file
      final File destFile = File('$APP_DATA_DIR/$VALUE_MAP_FILE');
      await importFile.copy(destFile.path);
      
      // Reload the map
      await loadValueMap();
      
      return true;
    } catch (e) {
      print("Error importing value map: $e");
      return false;
    }
  }
  
  // Shuffle and regenerate all mapping files
  static Future<bool> shuffleFiles() async {
    try {
      // First ensure directory exists
      await setupAppDirectory();
      
      Directory directory = Directory(APP_DATA_DIR);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print("Created directory for shuffle: $APP_DATA_DIR");
      }
      
      // Clear existing files
      final asciiFile = File('$APP_DATA_DIR/$ASCII_MAP_FILE');
      final valueFile = File('$APP_DATA_DIR/$VALUE_MAP_FILE');
      
      if (await asciiFile.exists()) {
        await asciiFile.delete();
      }
      
      if (await valueFile.exists()) {
        await valueFile.delete();
      }
      
      // Create new files
      await createAsciiMap();
      await createValueMap();
      
      // Verify files were created
      if (!await asciiFile.exists() || !await valueFile.exists()) {
        throw Exception("Failed to create new files");
      }
      
      // Reload maps
      await loadAsciiMap();
      await loadValueMap();
      
      return true;
    } catch (e) {
      print("Error shuffling files: $e");
      return false;
    }
  }
  
  // Request appropriate storage permissions based on Android version
  static Future<bool> _requestStoragePermissions(int sdkVersion) async {
    if (!Platform.isAndroid) return true;
    
    try {
      Fluttertoast.cancel(); // Cancel any existing toasts
      
      // For Android 13+ (API 33+)
      if (sdkVersion >= 33) { 
        // Use photos/media permission instead of MANAGE_EXTERNAL_STORAGE
        print("Using photos permission for Android 13+");
        
        PermissionStatus status = await Permission.photos.status;
        print("Photos permission status before request: $status");
        
        if (status.isGranted) {
          print("Photos permission already granted");
          return true;
        }
        
        status = await Permission.photos.request();
        print("Photos permission status after request: $status");
        
        if (!status.isGranted) {
          Fluttertoast.showToast(
            msg: 'Storage permission is required for export/import operations',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.red,
          );
          return false;
        }
        return true;
      } 
      // For Android 10-12
      else if (sdkVersion >= 29) {
        PermissionStatus status = await Permission.storage.status;
        print("Storage permission status before request: $status");
        
        if (status.isGranted) {
          return true;
        }
        
        status = await Permission.storage.request();
        print("Storage permission status after request: $status");
        
        if (!status.isGranted) {
          Fluttertoast.showToast(
            msg: 'Storage permission is required for export/import operations',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.red,
          );
          return false;
        }
        return true;
      } 
      // For Android 9 and below
      else {
        PermissionStatus status = await Permission.storage.status;
        if (status.isGranted) {
          return true;
        }
        
        status = await Permission.storage.request();
        return status.isGranted;
      }
    } catch (e) {
      print("Error requesting permissions: $e");
      return false;
    }
  }
  
  // Show a toast message
  static void showToast(String message, {bool isError = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red : Colors.green,
      textColor: Colors.white,
    );
  }
} 