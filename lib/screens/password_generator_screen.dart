import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/password_generator.dart';
import '../services/file_service.dart';
import '../theme/app_theme.dart';
import 'eula_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../main.dart' show requestStoragePermissions;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:app_settings/app_settings.dart';

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});

  @override
  State<PasswordGeneratorScreen> createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> with WidgetsBindingObserver {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  
  String _generatedPassword = '';
  bool _isGenerating = false;
  bool _showPermissionButton = false;
  bool _isInitialized = false;
  
  // Add this field to track what operation was interrupted by permission request
  String _pendingOperation = "";

  @override
  void initState() {
    super.initState();
    _lengthController.text = '100'; // Default length
    
    // Initialize files without permission checks
    _initializeFiles();
    
    // Set up lifecycle observer
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    _lengthController.dispose();
    _keyController.dispose();
    // Unregister from lifecycle events
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Handle app lifecycle state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from background (like returning from settings)
    if (state == AppLifecycleState.resumed) {
      print("App resumed, checking permissions again");
      
      // Cancel any existing toasts first
      Fluttertoast.cancel();
      
      // Check if we're in the middle of a file operation
      if (_isGenerating) {
        // Re-check for storage permissions with multiple attempts
        _checkStoragePermissions().then((hasPermission) {
          if (hasPermission) {
            print("Permissions granted after returning from settings");
            _showSuccessToast("Permissions granted!");
            
            // Resume the operation that was in progress
            if (_pendingOperation == "export") {
              _resumeExportFiles();
            } else if (_pendingOperation == "importAscii") {
              _resumeImportAsciiMapFile();
            } else if (_pendingOperation == "importValue") {
              _resumeImportValueMapFile();
            }
          }
        });
        
        // Add a longer delay for Android's permission system
        Future.delayed(const Duration(milliseconds: 1500), () {
          _checkStoragePermissions().then((hasPermission) {
            if (hasPermission) {
              print("Permissions granted on delayed check");
            }
          });
        });
      }
    }
  }

  // Initialize files without permission checks
  Future<void> _initializeFiles() async {
    try {
      // FileService.initializeFiles() now returns a boolean
      bool initialized = await FileService.initializeFiles();
      
      setState(() {
        _isInitialized = initialized;
        // Always hide the permission button since we're using private storage
        _showPermissionButton = false;
      });
      
      if (!initialized) {
        _showErrorToast('Failed to initialize app files');
      }
    } catch (e) {
      print("Error initializing files: $e");
      setState(() {
        _isInitialized = false;
        _showPermissionButton = false;
      });
      _showErrorToast('Error setting up files: ${e.toString()}');
    }
  }

  // Remove the _checkPermissionStatus method or update it to never show the button
  Future<void> _checkPermissionStatus() async {
    // Always set to false - we don't need permissions for private storage
    setState(() {
      _showPermissionButton = false;
    });
  }

  Future<void> _generatePassword() async {
    // Validate inputs
    if (_idController.text.isEmpty) {
      _showErrorToast('Please enter an ID');
      return;
    }

    int length;
    try {
      length = int.parse(_lengthController.text);
      if (length < 1) {
        _showErrorToast('Length cannot be less than 1');
        return;
      }
    } catch (e) {
      _showErrorToast('Please enter a valid length');
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    // Generate a random key if empty
    if (_keyController.text.isEmpty) {
      String randomKey = FileService.generateRandomKey(5);
      setState(() {
        _keyController.text = randomKey;
      });
    }

    try {
      // Always check for files existence on Windows platform
      if (Platform.isWindows) {
        await FileService.setupAppDirectory();
        Directory directory = Directory(FileService.APP_DATA_DIR);
        
        // Create directory if it doesn't exist
        if (!await directory.exists()) {
          try {
            await directory.create(recursive: true);
            print("Created directory: ${FileService.APP_DATA_DIR}");
          } catch (e) {
            print("Error creating directory: $e");
            _showErrorToast('Error creating directory. Please try again.');
            setState(() {
              _isGenerating = false;
            });
            return;
          }
        }
        
        // Check for CSV files
        bool asciiExists = await File('${FileService.APP_DATA_DIR}/${FileService.ASCII_MAP_FILE}').exists();
        bool valueExists = await File('${FileService.APP_DATA_DIR}/${FileService.VALUE_MAP_FILE}').exists();
        
        if (!asciiExists || !valueExists) {
          print("CSV files missing, creating them now...");
          
          if (!asciiExists) {
            await FileService.createAsciiMap();
          } else {
            await FileService.loadAsciiMap();
          }
          
          if (!valueExists) {
            await FileService.createValueMap();
          } else {
            await FileService.loadValueMap();
          }
        } else {
          // Load existing files
          await FileService.loadAsciiMap();
          await FileService.loadValueMap();
        }
      } else {
        // For other platforms, use the original method
        bool filesReady = await _ensureFilesExist();
        if (!filesReady) {
          _showErrorToast('Unable to prepare required files');
          setState(() {
            _isGenerating = false;
          });
          return;
        }
      }
      
      // Now generate the password
      String password = PasswordGenerator.generatePassword(
        _idController.text,
        length,
        _keyController.text,
      );

      setState(() {
        _generatedPassword = password;
        _isGenerating = false;
      });

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: password));
      _showSuccessToast('Password copied to clipboard');
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      
      // Show a more user-friendly error message
      String errorMsg = 'Error generating password';
      if (e.toString().contains('Invalid Number')) {
        errorMsg = 'Error: Invalid character in input';
      } else if (e.toString().contains('Maps failed to load')) {
        errorMsg = 'Error: App files not properly initialized';
      } else {
        errorMsg = 'Unexpected error. Please try with different inputs.';
      }
      
      _showErrorToast(errorMsg);
      print('Password generation error: $e');
    }
  }

  void _showErrorToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  void _showSuccessToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }
  
  void _showWarningToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.CENTER,
      backgroundColor: Colors.orange,
      textColor: Colors.white,
    );
  }

  // Check and ensure the CSV files exist
  Future<bool> _ensureFilesExist() async {
    try {
      // First, set up the app directory path
      await FileService.setupAppDirectory();
      print("Checking files in: ${FileService.APP_DATA_DIR}");
      
      // Ensure directory exists
      Directory directory = Directory(FileService.APP_DATA_DIR);
      if (!await directory.exists()) {
        try {
          await directory.create(recursive: true);
          print("Created directory: ${FileService.APP_DATA_DIR}");
        } catch (e) {
          print("Error creating directory: $e");
          _showErrorToast('Unable to create directory. Please try again.');
          return false;
        }
      }
      
      // Try a test write to verify permissions
      try {
        final testFile = File('${FileService.APP_DATA_DIR}/test_write.txt');
        await testFile.writeAsString('Test write access');
        await testFile.delete();
        print("Directory is writable");
      } catch (e) {
        print("Directory is not writable: $e");
        _showErrorToast('Cannot write to storage. Please try again.');
        return false;
      }
      
      // Check ASCII map file
      bool asciiExists = await File('${FileService.APP_DATA_DIR}/${FileService.ASCII_MAP_FILE}').exists();
      bool valueExists = await File('${FileService.APP_DATA_DIR}/${FileService.VALUE_MAP_FILE}').exists();
      
      // Regenerate files if they don't exist
      if (!asciiExists || !valueExists) {
        print("One or more files missing, reinitializing");
        await FileService.initializeFiles();
        
        // Check again after initialization
        asciiExists = await File('${FileService.APP_DATA_DIR}/${FileService.ASCII_MAP_FILE}').exists();
        valueExists = await File('${FileService.APP_DATA_DIR}/${FileService.VALUE_MAP_FILE}').exists();
        
        if (!asciiExists || !valueExists) {
          _showErrorToast('Failed to create required files');
          return false;
        }
      }
      
      return true;
    } catch (e) {
      print("Error ensuring files exist: $e");
      _showErrorToast('Error checking files: ${e.toString()}');
      return false;
    }
  }

  // This method is simplified and no longer shows a button
  Future<void> _requestPermissions() async {
    _showSuccessToast('App ready to use!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PSWRD'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'theme') {
                Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
              } else if (value == 'eula') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EulaScreen()),
                );
              } else if (value == 'export_files') {
                // Export files functionality
                await _exportFiles();
              } else if (value == 'import_files') {
                // Import files functionality
                await _showImportDialog();
              } else if (value == 'shuffle_files') {
                // Shuffle files functionality
                await _shuffleFiles();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(Icons.dark_mode, size: 20),
                    SizedBox(width: 8),
                    Text('Toggle Theme'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export_files',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 20),
                    SizedBox(width: 8),
                    Text('Export Files'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'import_files',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, size: 20),
                    SizedBox(width: 8),
                    Text('Import Files'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'shuffle_files',
                child: Row(
                  children: [
                    Icon(Icons.shuffle, size: 20),
                    SizedBox(width: 8),
                    Text('Shuffle Files'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'eula',
                child: Row(
                  children: [
                    Icon(Icons.description, size: 20),
                    SizedBox(width: 8),
                    Text('EULA'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 24.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate Secure Password',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Create unbreakable passwords with our advanced encryption algorithm.',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                TextFormField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: 'ID',
                    hintText: 'Enter your ID',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lengthController,
                  decoration: const InputDecoration(
                    labelText: 'Length',
                    hintText: 'Password length',
                    prefixIcon: Icon(Icons.format_size),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    labelText: 'Key (optional)',
                    hintText: 'Leave empty for random key',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isGenerating ? null : _generatePassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isGenerating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'GENERATE PASSWORD',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(height: 32),
                if (_generatedPassword.isNotEmpty) ...[
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Generated Password:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  // Select all button
                                  IconButton(
                                    icon: const Icon(Icons.select_all),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _generatedPassword));
                                      _showSuccessToast('Password copied to clipboard');
                                    },
                                    tooltip: 'Select all',
                                    iconSize: 20,
                                  ),
                                  // Copy button
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: _generatedPassword));
                                      _showSuccessToast('Password copied to clipboard');
                                    },
                                    tooltip: 'Copy to clipboard',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                              ),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                _generatedPassword,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'monospace',
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Password length: ${_generatedPassword.length} characters',
                                style: TextStyle(
                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                              if (_generatedPassword.length > 50)
                                const Text(
                                  '(Scroll horizontally to see more)',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // New methods for file management
  
  // Check storage permissions
  Future<bool> _checkStoragePermissions() async {
    // No permissions needed on Windows
    if (Platform.isWindows) return true;
    
    // Only Android needs permission checks
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;
      
      if (sdkVersion >= 33) {
        // For Android 13+, check Photos permission
        print("Using photos permission for Android 13+");
        final photosStatus = await Permission.photos.status;
        print("Photos permission status: $photosStatus");
        return photosStatus.isGranted;
      } else {
        // For Android 10-12, regular storage permission is sufficient
        final storageStatus = await Permission.storage.status;
        return storageStatus.isGranted;
      }
    }
    
    return true; // Default to true for non-Android platforms
  }

  // Export files as a ZIP
  Future<void> _exportFiles() async {
    try {
      setState(() {
        _isGenerating = true;
        _pendingOperation = "export"; // Track that we're in an export operation
      });
      
      Fluttertoast.cancel(); // Cancel any existing toasts
      
      // On Android, we need to check permissions
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;
        
        if (sdkVersion >= 33) {
          // For Android 13+, check Photos permission
          print("Using photos permission for Android 13+");
          final photosStatus = await Permission.photos.status;
          print("Photos permission status: $photosStatus");
          
          if (!photosStatus.isGranted) {
            // Request photos permission
            final requestStatus = await Permission.photos.request();
            print("Photos permission request result: $requestStatus");
            
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is required for export');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        } else {
          // For Android 10-12, regular storage permission is sufficient
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            final requestStatus = await Permission.storage.request();
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is required for export');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        }
      }
      
      // Execute the export
      String? exportPath = await FileService.exportFilesToZip();
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (exportPath != null) {
        if (Platform.isWindows) {
          _showSuccessToast('Files exported to Downloads folder');
        } else {
          _showSuccessToast('Files exported to Downloads folder');
        }
      } else {
        _showErrorToast('Failed to export files');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error during export: ${e.toString()}');
    }
  }
  
  // Show the import dialog
  Future<void> _showImportDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload Files'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select CSV files to import. Files must be in the proper format to be accepted.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _importAsciiMapFile();
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload ASCII Map'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _importValueMapFile();
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Value Map'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }
  
  // Import ASCII Map file
  Future<void> _importAsciiMapFile() async {
    try {
      setState(() {
        _isGenerating = true;
        _pendingOperation = "importAscii"; // Track that we're in an import ASCII operation
      });
      
      Fluttertoast.cancel(); // Cancel any existing toasts
      
      // Handle Android permission requirements
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;
        
        if (sdkVersion >= 33) {
          // For Android 13+, check Photos permission
          print("Using photos permission for Android 13+ import");
          final photosStatus = await Permission.photos.status;
          print("Photos permission status: $photosStatus");
          
          if (!photosStatus.isGranted) {
            // Request photos permission
            final requestStatus = await Permission.photos.request();
            print("Photos permission request result: $requestStatus");
            
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is required for import');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        } else {
          // Check storage permission for older Android versions
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            final requestStatus = await Permission.storage.request();
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is needed to import files');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        }
      }
      
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return; // User canceled the picker
      }
      
      String? filePath = result.files.single.path;
      if (filePath == null) {
        _showErrorToast('Could not get file path');
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return;
      }
      
      // Import the file
      bool success = await FileService.importAsciiMapFile(filePath);
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (success) {
        _showSuccessToast('ASCII map imported successfully');
      } else {
        _showErrorToast('Failed to import ASCII map');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error importing file: ${e.toString()}');
    }
  }
  
  // Import Value Map file
  Future<void> _importValueMapFile() async {
    try {
      setState(() {
        _isGenerating = true;
        _pendingOperation = "importValue"; // Track that we're in an import Value operation
      });
      
      Fluttertoast.cancel(); // Cancel any existing toasts
      
      // Handle Android permission requirements
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;
        
        if (sdkVersion >= 33) {
          // For Android 13+, check Photos permission
          print("Using photos permission for Android 13+ value map import");
          final photosStatus = await Permission.photos.status;
          print("Photos permission status: $photosStatus");
          
          if (!photosStatus.isGranted) {
            // Request photos permission
            final requestStatus = await Permission.photos.request();
            print("Photos permission request result: $requestStatus");
            
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is required for import');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        } else {
          // Check storage permission for older Android versions
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            final requestStatus = await Permission.storage.request();
            if (!requestStatus.isGranted) {
              _showErrorToast('Storage permission is needed to import files');
              setState(() {
                _isGenerating = false;
                _pendingOperation = "";
              });
              return;
            }
          }
        }
      }
      
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return; // User canceled the picker
      }
      
      String? filePath = result.files.single.path;
      if (filePath == null) {
        _showErrorToast('Could not get file path');
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return;
      }
      
      // Import the file
      bool success = await FileService.importValueMapFile(filePath);
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (success) {
        _showSuccessToast('Value map imported successfully');
      } else {
        _showErrorToast('Failed to import value map');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error importing file: ${e.toString()}');
    }
  }
  
  // Shuffle files and generate new maps
  Future<void> _shuffleFiles() async {
    // Confirm with the user first
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Shuffle Files'),
          content: const Text(
            'This will delete existing mapping files and generate new ones. '
            'All previously generated passwords will no longer be valid with the new files. '
            'Are you sure you want to continue?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONTINUE'),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirm) return;
    
    try {
      setState(() {
        _isGenerating = true;
      });
      
      // Perform the shuffle
      bool success = await FileService.shuffleFiles();
      
      setState(() {
        _isGenerating = false;
      });
      
      if (success) {
        _showSuccessToast('Files shuffled successfully');
      } else {
        _showErrorToast('Failed to shuffle files');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showErrorToast('Error shuffling files: ${e.toString()}');
    }
  }

  // Resume the export operation after permissions granted
  Future<void> _resumeExportFiles() async {
    try {
      print("Resuming export operation");
      
      // Execute the export directly now that we have permission
      String? exportPath = await FileService.exportFilesToZip();
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (exportPath != null) {
        _showSuccessToast('Files exported to Downloads folder');
      } else {
        _showErrorToast('Failed to export files');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error during export: ${e.toString()}');
    }
  }
  
  // Resume the import ASCII Map operation after permissions granted
  Future<void> _resumeImportAsciiMapFile() async {
    try {
      print("Resuming ASCII Map import operation");
      
      // Now we have permission, show the file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return; // User canceled the picker
      }
      
      String? filePath = result.files.single.path;
      if (filePath == null) {
        _showErrorToast('Could not get file path');
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return;
      }
      
      // Import the file
      bool success = await FileService.importAsciiMapFile(filePath);
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (success) {
        _showSuccessToast('ASCII map imported successfully');
      } else {
        _showErrorToast('Failed to import ASCII map');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error importing file: ${e.toString()}');
    }
  }
  
  // Resume the import Value Map operation after permissions granted
  Future<void> _resumeImportValueMapFile() async {
    try {
      print("Resuming Value Map import operation");
      
      // Now we have permission, show the file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return; // User canceled the picker
      }
      
      String? filePath = result.files.single.path;
      if (filePath == null) {
        _showErrorToast('Could not get file path');
        setState(() {
          _isGenerating = false;
          _pendingOperation = "";
        });
        return;
      }
      
      // Import the file
      bool success = await FileService.importValueMapFile(filePath);
      
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      
      if (success) {
        _showSuccessToast('Value map imported successfully');
      } else {
        _showErrorToast('Failed to import value map');
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _pendingOperation = "";
      });
      _showErrorToast('Error importing file: ${e.toString()}');
    }
  }
} 