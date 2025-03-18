import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'screens/password_generator_screen.dart';
import 'screens/eula_screen.dart';
import 'theme/app_theme.dart';
import 'services/file_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only request permissions for export features
Future<bool> requestStoragePermissions() async {
  // Skip permission checks on non-Android platforms
  if (!Platform.isAndroid) return true;
  
  // Cancel any existing toasts first
  Fluttertoast.cancel();
  
  try {
    // Get Android SDK version
    final sdkVersion = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    print("Android SDK version: $sdkVersion");
    
    // For Android 13+, use photos permission
    if (sdkVersion >= 33) {
      print("Using photos permission for Android 13+");
      final photosStatus = await Permission.photos.status;
      print("Photos permission status: $photosStatus");
      
      if (photosStatus.isGranted) {
        return true;
      }
      
      // Request photos permission
      final requestStatus = await Permission.photos.request();
      print("Photos permission request result: $requestStatus");
      
      if (!requestStatus.isGranted) {
        Fluttertoast.showToast(
          msg: 'Storage permission needed for export/import operations',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
        return false;
      }
      
      return true;
    }
    
    // For older Android versions, check regular storage permission
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    
    // Request regular storage permission
    var requestStatus = await Permission.storage.request();
    print("Storage permission request result: $requestStatus");
    
    if (!requestStatus.isGranted) {
      Fluttertoast.showToast(
        msg: 'Storage permission needed for export operations',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
      return false;
    }
    
    return true;
  } catch (e) {
    print("Error requesting export permissions: $e");
    return false;
  }
}

// Check if this is first app launch
Future<bool> isFirstLaunch() async {
  final prefs = await SharedPreferences.getInstance();
  bool isFirstLaunch = prefs.getBool('first_launch') ?? true;
  if (isFirstLaunch) {
    // Set the flag to false for future launches
    await prefs.setBool('first_launch', false);
  }
  return isFirstLaunch;
}

// Initialize app data - no permission checks needed
Future<bool> initializeApp() async {
  try {
    // Setup the app directory (private storage or Windows-specific directory)
    await FileService.setupAppDirectory();
    
    // Create directory if it doesn't exist
    Directory directory = Directory(FileService.APP_DATA_DIR);
    if (!await directory.exists()) {
      try {
        await directory.create(recursive: true);
        print("Created directory: ${FileService.APP_DATA_DIR}");
      } catch (e) {
        print("Error creating directory: $e");
        Fluttertoast.showToast(
          msg: 'Error creating app directory: ${e.toString()}',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
        return false;
      }
    }
    
    // For Windows, we'll delay initialization until password generation
    if (Platform.isWindows) {
      print("Running on Windows, will initialize files when needed");
      return true;
    }
    
    // Initialize the files for non-Windows platforms
    return await FileService.initializeFiles();
  } catch (e) {
    print("Error initializing app: $e");
    Fluttertoast.showToast(
      msg: 'Error initializing app: ${e.toString()}',
      toastLength: Toast.LENGTH_LONG,
      backgroundColor: Colors.red,
    );
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize app data
  bool initialized = await initializeApp();
  
  // Check if this is first launch
  bool firstLaunch = await isFirstLaunch();
  
  // Run the app with initialization status and first launch info
  runApp(MyApp(initialized: initialized, isFirstLaunch: firstLaunch));
}

class MyApp extends StatelessWidget {
  final bool initialized;
  final bool isFirstLaunch;
  
  const MyApp({super.key, this.initialized = false, this.isFirstLaunch = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'PSWRD',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: isFirstLaunch 
                ? const EulaFirstScreen() 
                : const PasswordGeneratorScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

// First launch EULA screen
class EulaFirstScreen extends StatelessWidget {
  const EulaFirstScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('End User License Agreement'),
        automaticallyImplyLeading: false, // Disable back button
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome to PSWRD',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Before you begin, please read and accept our End User License Agreement.',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                height: 400,
                child: const SingleChildScrollView(
                  child: EulaContent(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const PasswordGeneratorScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'I ACCEPT THE TERMS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Extracted EULA content to be reused in both screens
class EulaContent extends StatelessWidget {
  const EulaContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection(
          title: '1. Acceptance of Terms',
          content: 'By using this application, you agree to be bound by the terms and conditions outlined in this agreement.',
        ),
        _buildSection(
          title: '2. License Grant',
          content: 'Subject to your compliance with these terms, you are granted a limited, non-exclusive, non-transferable license to use the application for personal, non-commercial purposes.',
        ),
        _buildSection(
          title: '3. Password Generation',
          content: 'The application generates passwords based on input parameters. The developer does not store, access, or transmit your passwords or input data to any third-party servers.',
        ),
        _buildSection(
          title: '4. Limitation of Liability',
          content: 'THE DEVELOPER IS NOT RESPONSIBLE FOR ANY PASSWORD OR INTERNAL FILES LEAKAGE. The application operates entirely on your device, and the security of generated passwords depends on how you manage them after generation.',
        ),
        _buildSection(
          title: '5. Data Storage',
          content: 'All configuration files are stored securely in the app\'s private storage area, which is inaccessible to other applications unless the device is rooted. These files are used solely for password generation and are not shared with any third parties.',
        ),
        _buildSection(
          title: '6. No Warranty',
          content: 'THE APPLICATION IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.',
        ),
        _buildSection(
          title: '7. Application Permissions',
          content: 'This application does not require storage permissions for normal operation. Storage permissions are only requested when exporting files to your device\'s Download folder, which is an optional feature.',
        ),
        _buildSection(
          title: '8. Changes to this Agreement',
          content: 'The developer reserves the right to modify this agreement at any time. Continued use of the application after such changes constitutes your acceptance of the modified agreement.',
        ),
      ],
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
