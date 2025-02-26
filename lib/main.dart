import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dynamicform.dart';
import 'package:flutter/foundation.dart';

final List<Map<String, dynamic>> formJson = [
//    {
//     'name': '10210298',
//     'label': 'Are handwashing facilities available?',
//     'type': 'number',
//     'required': true,
//     'min': 18,
//     'max': 100,
//     'hasAttachments': true,
//     'attachmentsRequired': true
    

//   },
//   {
//   "name" : "question_1",
//   "type" : "text",
//   "label" : "What is the recommended temperature for storing perishable foods in a refrigerator?",
//   "options":"",
//   "required" :true,
//   "hasAttachments" : true,
//   "showAttachmentsOn" : "",
//   "disableAttachmentsOn" :"",
//   "attachmentsRequired" : true
// },
{
  "name": "question1iio",
  "type": "radio",
  "label": "Do you have a car?",


},
{
  "name": "question1",
  "type": "radio",
  "label": "Do you have a car?",
  "options": ["Yes", "No"],
  "branching": {
    "Yes": "car_details",
    "No": "transportation"
  }
},
{
  "name": "car_details",
  "type": "text",
  "label": "What is your car's model?"
  // This will automatically get prevQuestion: "question1"
},
{
  "name": "transportation",
  "type": "text",
  "label": "How do you usually travel?"
  // This will automatically get prevQuestion: "question1"
},
{
  'name': 'dropdown_field',
  'type': 'dropdown',
  'label': 'what is your  ratting of this place',
  'options': ['1', '2', '3', '4', '5', '6'],
  'required': true,
  'hasAttachments': true,
  'requireAttachmentsOn': ['1', '4', '5'],  // Array of values that require attachments
  'disableAttachmentsOn': ['2', '6'],       // Array of values that disable attachments
  'hasComments': true
},

  // {
  //   'name': 'cleaning_storage',
  //   'type': 'radio',
  //   'label': 'Is there a place to store cleaning chemicals?',
  //   'options': ['Yes', 'No'],
  //   'required': true,
  //   'hasAttachments': true,
  //   'requireAttachmentsOn': 'Yes',
  //   'showAttachmentsOn': 'Yes',
  //   'disableAttachmentsOn': 'No',
  //   'hasComments': true
  // },
  {
    'name': 'cleaning_storage_233',
    'type': 'file',
    'label': 'Is there a place to store cleaning chemicals?',
    'required': true,
    'hasAttachments': true,
    'requireAttachmentsOn': '',
    'showAttachmentsOn': '',
    'disableAttachmentsOn': '',
    // 'hasComments': true
  },
  {
    'name': 'pest_control',
    'type': 'radio',
    'label': 'Is there evidence of pest infestation?',
    'options': ['Yes', 'No'],
    'required': true,
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
          'required': true,
        },
        {
          'name': 'pest_location',
          'type': 'text',
          'inputType': 'text',
          'label': 'Where was the pest evidence found?',
          'required': true,
        }
      ]
    }
  },
  {
    'name': 'temperature_monitoring',
    'type': 'dropdown',
    'label': 'Current refrigerator temperature?',
    'options': ['32-36°F', '37-40°F', '41-45°F', 'Above 45°F'],
    'required': true,
    'hasAttachments': true,
    'showAttachmentsOn': 'Above 45°F',
    'disableAttachmentsOn': '32-36°F',
  },
  {
    'name': 'food_storage',
    'type': 'text',
    'inputType': 'number',
    'label': 'Current freezer temperature (°F)?',
    'required': ['required', 'number']
  },
  {
    'name': 'cleaning_schedule',
    'type': 'dropdown',
    'label': 'How often is deep cleaning performed?',
    'options': ['Daily', 'Weekly', 'Bi-weekly', 'Monthly'],
    'required': true,
    'hasAttachments': false,
  },
  {
    'name': 'food_labeling',
    'type': 'radio',
    'label': 'Are all stored food items labeled?',
    'options': ['Yes', 'No'],
    'required': true,
    'hasAttachments': true,
    'showAttachmentsOn': 'No',
    'disableAttachmentsOn': 'Yes',
  },
  {
    'name': 'sanitizer_concentration',
    'type': 'dropdown',
    'label': 'Sanitizer concentration level?',
    'options': ['50-99 ppm', '100-199 ppm', '200-400 ppm', 'Above 400 ppm'],
    'required': true,
    'hasAttachments': true,
    'showAttachmentsOn': 'Above 400 ppm',
    'hasComments': true
  },
  {
    'name': 'waste_disposal',
    'type': 'radio',
    'label': 'Is waste properly disposed of?',
    'options': ['Yes', 'No'],
    'required': true,
    'hasAttachments': false,
     'hasComments': true

  },
  {
    'name': 'maintenance_issues',
    'type': 'text',
    // 'inputType': 'text',
    'label': 'List any maintenance issues:',
    'required': true,
    'hasComments': true

  },
  {
    'name': 'hand_washing_facilities',
    'type': 'radio',
    'label': 'Are handwashing facilities available?',
    'options': ['Yes', 'No'],
    'required': true,
    'hasAttachments': true,
    'showAttachmentsOn': 'No',
    'disableAttachmentsOn': 'Yes',
    'hasComments': true

  },
   
  {
    "name" :"question_5",
    "type" : "number",
    "label" : "what is fridge temp ",
    "required" : ["required"],
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
