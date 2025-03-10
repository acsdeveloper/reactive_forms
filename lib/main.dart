import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dynamicform.dart';
import 'package:flutter/foundation.dart';

import 'jsondata.dart';



void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Only request permissions if not running on web
  if (!kIsWeb) {
    await Permission.camera.request();
    await Permission.storage.request();
    if (await Permission.photos.shouldShowRequestRationale) {
      await Permission.photos.request();
    }
  }
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KitchenInspectionScreen(),
    );
  }
}

class KitchenInspectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Kitchen Inspection')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: DynamicForm(
          fontFamily: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          context: context,
          showOneByOne: true,
          primaryColor: Colors.black,
          formJson: formJson, 
          onSubmit: (formData, attachments) {
            print(formData);
            print(attachments);
          },
        ),
      ),
    );
  }
}
