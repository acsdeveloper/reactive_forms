import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dynamicform.dart';

final List<Map<String, dynamic>> formJson = [
  {
    'name': 'cleaning_storage',
    'type': 'radio',
    'label': 'Is there a place to store cleaning chemicals?',
    'options': ['Yes', 'No'],
    'validators': ['required'],
    'hasAttachments': true,
    'requireAttachmentsOn': 'Yes',
    'showAttachmentsOn': 'Yes',
    'disableAttachmentsOn': 'No',
    'hasComments': true
  },
  {
    'name': 'cleaning_storage_233',
    'type': 'file',
    'label': 'Is there a place to store cleaning chemicals?',
    'validators': ['required'],
    'hasAttachments': true,
    'hasComments': true
  },
  {
    'name': 'pest_control',
    'type': 'radio',
    'label': 'Is there evidence of pest infestation?',
    'options': ['Yes', 'No'],
    'validators': ['required'],
    'hasAttachments': true,
    'requireAttachmentsOn': 'Yes',
    'showAttachmentsOn': 'Yes',
    'disableAttachmentsOn': 'No',
    'subQuestions': {
      'Yes': [
        {
          'name': 'pest_type',
          'type': 'dropdown',
          'label': 'What type of pest was found?',
          'options': ['Rodents', 'Insects', 'Other'],
          'validators': ['required'],
        },
        {
          'name': 'pest_location',
          'type': 'text',
          'inputType': 'text',
          'label': 'Where was the pest evidence found?',
          'validators': ['required'],
        }
      ]
    }
  },
  {
    'name': 'temperature_monitoring',
    'type': 'dropdown',
    'label': 'Current refrigerator temperature?',
    'options': ['32-36°F', '37-40°F', '41-45°F', 'Above 45°F'],
    'validators': ['required'],
    'hasAttachments': true,
    'showAttachmentsOn': 'Above 45°F',
    'disableAttachmentsOn': '32-36°F',
  },
  {
    'name': 'food_storage',
    'type': 'text',
    'inputType': 'number',
    'label': 'Current freezer temperature (°F)?',
    'validators': ['required', 'number']
  },
  {
    'name': 'cleaning_schedule',
    'type': 'dropdown',
    'label': 'How often is deep cleaning performed?',
    'options': ['Daily', 'Weekly', 'Bi-weekly', 'Monthly'],
    'validators': ['required'],
    'hasAttachments': false,
  },
  {
    'name': 'food_labeling',
    'type': 'radio',
    'label': 'Are all stored food items labeled?',
    'options': ['Yes', 'No'],
    'validators': ['required'],
    'hasAttachments': true,
    'showAttachmentsOn': 'No',
    'disableAttachmentsOn': 'Yes',
  },
  {
    'name': 'sanitizer_concentration',
    'type': 'dropdown',
    'label': 'Sanitizer concentration level?',
    'options': ['50-99 ppm', '100-199 ppm', '200-400 ppm', 'Above 400 ppm'],
    'validators': ['required'],
    'hasAttachments': true,
    'showAttachmentsOn': 'Above 400 ppm',
    'hasComments': true
  },
  {
    'name': 'waste_disposal',
    'type': 'radio',
    'label': 'Is waste properly disposed of?',
    'options': ['Yes', 'No'],
    'validators': ['required'],
    'hasAttachments': false,
     'hasComments': true

  },
  {
    'name': 'maintenance_issues',
    'type': 'text',
    'inputType': 'text',
    'label': 'List any maintenance issues:',
    'validators': ['required'],
    'hasComments': true

  },
  {
    'name': 'hand_washing_facilities',
    'type': 'radio',
    'label': 'Are handwashing facilities available?',
    'options': ['Yes', 'No'],
    'validators': ['required'],
    'hasAttachments': true,
    'showAttachmentsOn': 'No',
    'disableAttachmentsOn': 'Yes',
    'hasComments': true

  },
    {
    'name': '10210298',
    'label': 'Are handwashing facilities available?',
    'type': 'number',
    'validators': ['required'],
    'min': 18,
    'max': 100,
    

  },
  {
    "name" :"question_5",
    "type" : "number",
    "label" : "what is fridge temp ",
    "validators" : ["required"],
    "hasAttachments" : true,
    "requireAttachmentsOn" : "",
    "showAttachmentsOn" : "",
    "disableAttachmentsOn" : "",
    'min': 18,
    'max': 100,
   
    }
  
];

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize permissions
  await Permission.camera.request();
  await Permission.storage.request();
  if (await Permission.photos.shouldShowRequestRationale) {
    await Permission.photos.request();
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
