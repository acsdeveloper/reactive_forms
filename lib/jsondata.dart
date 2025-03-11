final List<Map<String, dynamic>> formJson = [
  {
    "name": "name",
    "type": "text",
    "label": "What is your name?",
    "required": true,
    "validators": ["required"]
  },
  {
    "name": "has_allergies",
    "type": "radio",
    "label": "Do you have any allergies?",
    "options": ["Yes", "No"],
    "required": true,
    "validators": ["required"]
  },
  {
    "name": "allergies_details",
    "type": "text",
    "label": "Please describe your allergies",
    "required": true,
    "validators": ["required"],
    "showWhen": {
      "has_allergies": "Yes"
    }
  },
  {
    "name": "contact_method",
    "type": "radio",
    "label": "Preferred contact method",
    "options": ["Phone", "Email", "Mail"],
    "required": true,
    "validators": ["required"]
  },
  {
    "name": "phone_number",
    "type": "text",
    "label": "Phone number",
    "required": true,
    "validators": ["required"],
    "showWhen": {
      "contact_method": "Phone"
    }
  },
  {
    "name": "email_address",
    "type": "text",
    "label": "Email address",
    "required": true,
    "validators": ["required"],
    "showWhen": {
      "contact_method": "Email"
    }
  },
  // {
  //   "name": "feedback",
  //   "type": "text",
  //   "label": "Any additional comments?",
  //   "required": false
  // }
];// [
//   {
//   "name": "preferences",
//   "type": "multiselect",
//   "label": "Select your preferences",
//   "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
//   "required": false
// },
// //    {
// //     'name': '10210298',
// //     'label': 'Are handwashing facilities available?',
// //     'type': 'number',
// //     'required': true,
// //     'min': 18,
// //     'max': 100,
// //     'hasAttachments': true,
// //     'attachmentsRequired': true
    

// //   },
// //   {
// //   "name" : "question_1",
// //   "type" : "text",
// //   "label" : "What is the recommended temperature for storing perishable foods in a refrigerator?",
// //   "options":"",
// //   "required" :true,
// //   "hasAttachments" : true,
// //   "showAttachmentsOn" : "",
// //   "disableAttachmentsOn" :"",
// //   "attachmentsRequired" : true
// // },
// {
//   "name": "questio90",
//   "type": "radio",
//   "hasComments": true,
//   "requiredCommentsOn": "Yes",  // or any other value that should trigger required comments
//   // ... other field properties
// },


// {
//   "name": "question1iio",
//   "type": "radio",
//   "label": "Do you have a car?",


// },
// {
//     "name": "question_1",
//     "type": "radio",
//     "label": "What is the dog s name?",
    
//     "required": true,
//     "hasAttachments": false,
//     "disableAttachmentsOn": "NO",
//     "requireAttachmentsOn": "YES",
//     "hasSubQuestions": false,
//     "min": "",
//     "max": "",
//     "hasComments": false,
//     "commentRequired": false,
//      "branching": {
//      "Yes": "car_details",
//      "No": "question1"

     
//       },
   
//     "subQuestionsId": ""
//   },
// {
//   "name": "question1",
//   "type": "radio",
//   "label": "Do you have a car?",
//   "options": ["Yes", "No"],
//   "branching": {
//     "Yes": "car_details",
//    "No": "end"
//   }
// },
// {
//   "name": "car_details",
//   "type": "text",
//   "label": "What is your car's model?"
//   // This will automatically get prevQuestion: "question1"
// },
// {
//   "name": "transportation",
//   "type": "text",
//   "label": "How do you usually travel?"
//   // This will automatically get prevQuestion: "question1"
// },
// {
//   'name': 'dropdown_field',
//   'type': 'dropdown',
//   'label': 'what is your  ratting of this place',
//   'options': ['1', '2', '3', '4', '5', '6'],
//   'required': true,
//   'hasAttachments': true,
//   'requireAttachmentsOn': ['1', '4', '5'],  // Array of values that require attachments
//   'disableAttachmentsOn': ['2', '6'],       // Array of values that disable attachments
//   'hasComments': true
// },

//   // {
//   //   'name': 'cleaning_storage',
//   //   'type': 'radio',
//   //   'label': 'Is there a place to store cleaning chemicals?',
//   //   'options': ['Yes', 'No'],
//   //   'required': true,
//   //   'hasAttachments': true,
//   //   'requireAttachmentsOn': 'Yes',
//   //   'showAttachmentsOn': 'Yes',
//   //   'disableAttachmentsOn': 'No',
//   //   'hasComments': true
//   // },
//   {
//     'name': 'cleaning_storage_233',
//     'type': 'file',
//     'label': 'Is there a place to store cleaning chemicals?',
//     'required': true,
//     'hasAttachments': true,
//     'requireAttachmentsOn': '',
//     'showAttachmentsOn': '',
//     'disableAttachmentsOn': '',
//     // 'hasComments': true
//   },
//   {
//     'name': 'pest_control',
//     'type': 'radio',
//     'label': 'Is there evidence of pest infestation?',
//     'options': ['Yes', 'No'],
//     'required': true,
//     'hasAttachments': true,
//     'requireAttachmentsOn': 'Yes',
//     'showAttachmentsOn': 'Yes',
//     'disableAttachmentsOn': 'No',
//     'subQuestions': {
//       'Yes': [
//         {
//           'name': 'pest_type',
//           'type': 'dropdown',
//           'label': 'What type of pest was found?',
//           'options': ['Rodents', 'Insects', 'Other'],
//           'required': true,
//         },
//         {
//           'name': 'pest_location',
//           'type': 'text',
//           'inputType': 'text',
//           'label': 'Where was the pest evidence found?',
//           'required': true,
//         }
//       ]
//     }
//   },
//   {
//     'name': 'temperature_monitoring',
//     'type': 'dropdown',
//     'label': 'Current refrigerator temperature?',
//     'options': ['32-36°F', '37-40°F', '41-45°F', 'Above 45°F'],
//     'required': true,
//     'hasAttachments': true,
//     'showAttachmentsOn': 'Above 45°F',
//     'disableAttachmentsOn': '32-36°F',
//   },
//   {
//     'name': 'food_storage',
//     'type': 'text',
//     'inputType': 'number',
//     'label': 'Current freezer temperature (°F)?',
//     'required': ['required', 'number']
//   },
//   {
//     'name': 'cleaning_schedule',
//     'type': 'dropdown',
//     'label': 'How often is deep cleaning performed?',
//     'options': ['Daily', 'Weekly', 'Bi-weekly', 'Monthly'],
//     'required': true,
//     'hasAttachments': false,
//   },
//   {
//     'name': 'food_labeling',
//     'type': 'radio',
//     'label': 'Are all stored food items labeled?',
//     'options': ['Yes', 'No'],
//     'required': true,
//     'hasAttachments': true,
//     'showAttachmentsOn': 'No',
//     'disableAttachmentsOn': 'Yes',
//   },
//   {
//     'name': 'sanitizer_concentration',
//     'type': 'dropdown',
//     'label': 'Sanitizer concentration level?',
//     'options': ['50-99 ppm', '100-199 ppm', '200-400 ppm', 'Above 400 ppm'],
//     'required': true,
//     'hasAttachments': true,
//     'showAttachmentsOn': 'Above 400 ppm',
//     'hasComments': true
//   },
//   {
//     'name': 'waste_disposal',
//     'type': 'radio',
//     'label': 'Is waste properly disposed of?',
//     'options': ['Yes', 'No'],
//     'required': true,
//     'hasAttachments': false,
//      'hasComments': true

//   },
//   {
//     'name': 'maintenance_issues',
//     'type': 'text',
//     // 'inputType': 'text',
//     'label': 'List any maintenance issues:',
//     'required': true,
//     'hasComments': true

//   },
//   {
//     'name': 'hand_washing_facilities',
//     'type': 'radio',
//     'label': 'Are handwashing facilities available?',
//     'options': ['Yes', 'No'],
//     'required': true,
//     'hasAttachments': true,
//     'showAttachmentsOn': 'No',
//     'disableAttachmentsOn': 'Yes',
//     'hasComments': true

//   },
   
//   {
//     "name" :"question_5",
//     "type" : "number",
//     "label" : "what is fridge temp ",
//     "required" : ["required"],
//     "hasAttachments" : true,
//     "requireAttachmentsOn" : "",
//     "showAttachmentsOn" : "",
//     "disableAttachmentsOn" : "",
//     'min': 18,
//     'max': 100,
   
//     }
  
// ];