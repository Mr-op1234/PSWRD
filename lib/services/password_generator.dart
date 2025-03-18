import 'dart:math' as math;
import 'package:decimal/decimal.dart';
import 'file_service.dart';

class PasswordGenerator {
  // Set high precision for decimal calculations
  static const int PRECISION = 1000;

  // Generate the password using the provided algorithm
  static String generatePassword(String id, int length, String key) {
    try {
      // Convert ID to binary, then to decimal
      String binaryId = binChars(id);
      
      // Ensure we have a valid binaryId
      if (binaryId.isEmpty) {
        throw Exception("Failed to convert ID to binary format");
      }
      
      Decimal idVal = Decimal.parse('0.' + binaryId);
      
      // Process key
      String processedKey = getAscii(key);
      
      // Ensure we have a valid key
      if (processedKey.isEmpty) {
        processedKey = '12345'; // Default if conversion fails
      }
      
      int keyValue;
      try {
        keyValue = int.parse(processedKey);
      } catch (e) {
        print("Error parsing key to int: $e, using default value");
        keyValue = 12345; // Fallback to default
      }
      
      // Ensure key is odd for better entropy
      if (keyValue % 2 == 0) {
        keyValue += 1;
      }
      
      String encryptedPassword = '';
      
      for (int i = 0; i < length; i++) {
        try {
          // Multiply and split into integer/fractional parts
          Decimal prod = idVal * Decimal.parse(keyValue.toString());
          
          // Safely extract int part
          String prodStr = prod.toString();
          int intPart;
          
          if (prodStr.contains('.')) {
            intPart = int.parse(prodStr.split('.')[0]);
          } else {
            intPart = prod.toBigInt().toInt();
          }
          
          Decimal decPart = prod - Decimal.parse(intPart.toString());
          
          // Calculate index and update encrypted password
          int indVal = intPart % 36;
          
          // Check if the index is valid
          if (FileService.valueMap.containsKey(indVal)) {
            encryptedPassword += FileService.valueMap[indVal] ?? '';
          } else {
            // Fallback to a safe character if the index is missing
            encryptedPassword += 'x';
          }
          
          // Update idVal with fractional part and add entropy
          idVal = decPart + Decimal.parse('0.000000000001'); // Prevent zero decay
          
          // Add non-linear transformation (square root)
          try {
            double idValDouble = double.parse(idVal.toString());
            if (idValDouble > 0) {
              idVal = Decimal.parse(math.sqrt(idValDouble).toString());
            }
          } catch (e) {
            // If the conversion fails, use a small non-zero value
            idVal = Decimal.parse('0.1');
          }
        } catch (e) {
          print("Error in iteration $i: $e");
          // Add a fallback character and continue
          encryptedPassword += 'e';
          // Reset idVal to prevent cascading errors
          idVal = Decimal.parse('0.5');
        }
      }
      
      return encryptedPassword;
    } catch (e) {
      print("Error generating password: $e");
      throw Exception("Failed to generate password: $e");
    }
  }
  
  // Convert a string to its binary representation using ASCII mappings
  static String binChars(String x) {
    try {
      if (x.isEmpty) {
        return "101010"; // Return a default value if input is empty
      }
      
      x = x.toLowerCase();
      List<String> chars = x.split('');
      String num = '';
      
      // Map each character to its ASCII code
      for (String char in chars) {
        bool found = false;
        for (MapEntry<int, String> entry in FileService.asciiMap.entries) {
          if (char == entry.value) {
            num += entry.key.toString();
            found = true;
            break;
          }
        }
        
        // If character not found in the map, use a default value
        if (!found) {
          num += '97'; // ASCII for 'a'
        }
      }
      
      // Ensure we have a valid number
      if (num.isEmpty) {
        return "101010"; // Return a default value
      }
      
      // Try parsing the number, handling potential errors
      int decimalValue;
      try {
        decimalValue = int.parse(num);
      } catch (e) {
        print("Error parsing in binChars: $e");
        return "101010"; // Return a default value if parsing fails
      }
      
      String binaryString = decimalValue.toRadixString(2);
      return binaryString;
    } catch (e) {
      print("Error in binChars: $e");
      return "101010"; // Return a default value if any error occurs
    }
  }
  
  // Convert input string to numeric key using ASCII mappings
  static String getAscii(String x) {
    try {
      if (x.isEmpty) {
        return "12345"; // Default value if input is empty
      }
      
      x = x.toLowerCase();
      List<String> chars = x.split('');
      String result = '';
      
      // Map each character to its ASCII code
      for (String char in chars) {
        bool found = false;
        for (MapEntry<int, String> entry in FileService.asciiMap.entries) {
          if (char == entry.value) {
            result += entry.key.toString();
            found = true;
            break;
          }
        }
        
        // If character not found in the map, use a default value
        if (!found) {
          result += '97'; // ASCII for 'a'
        }
      }
      
      return result.isEmpty ? '12345' : result; // Default value if conversion fails
    } catch (e) {
      print("Error in getAscii: $e");
      return "12345"; // Default value if any error occurs
    }
  }
} 