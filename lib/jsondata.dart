final List<Map<String, dynamic>> formJson = [
  {
    "name": "question_1",
    "type": "radio",
    "label": "Is the fridge operating between 0-5°C?",
    "options": ["A1", "B1", "C1", "D1"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["A1"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": true
  },
  {
    "name": "question_2",
    "type": "radio",
    "label": "Is the freezer operating below -18°C?",
    "options": ["Yes", "No"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": false,
    "showWhen": {
      "question_1": ["A1", "B1"]
    }
  },
  {
    "name": "question_3",
    "type": "number",
    "label": "Was the temperature checked twice today (AM & PM)?",
    "required": true,
    "hasAttachments": false,
    "max": 240
  },
  {
    "name": "question_4",
    "type": "number",
    "label": "Was the jelly pot or thermometer used to check the temperature?",
    "required": true,
    "hasAttachments": false,
    "max": 240
  },
  {
    "name": "question_5",
    "type": "number",
    "label": "Was any issue found during the temperature check?",
    "required": true,
    "hasAttachments": false,
    "disableAttachmentsOn": ["NO"],
    "showWhen": {
      "question_2": ["Yes"],
      "question_1": ["A1"]
    }
  },
  {
    "name": "question_6",
    "type": "text",
    "label": "If an issue was found, describe the problem.",
    "required": true,
    "hasAttachments": true,
    "requiredAttachmentsOn": true,
  },
  {
    "name": "question_7",
    "type": "radio",
    "label": "Were corrective actions taken to resolve the issue?",
    "options": ["Yes", "No"],
    "required": true,
    "hasAttachments": true,
    "hasComments": false
  },
  {
    "name": "question_8",
    "type": "number",
    "label": "If corrective actions were taken, describe them.",
    "required": true,
    "hasAttachments": false,
    "max": 240
  }
];

/// Sample initial values for autofill demonstration
final Map<String, dynamic> sampleInitialValues = {
  // question_1: radio, hasAttachments
  'question_1': 'A1',
  'question_1_comment': 'This is a comment for question 1',
  // 'question_1_attachments': [
  //   {
  //     'fileName': 'fridge_report.pdf',
  //     'fileType': 'pdf',
  //     'file': null,
  //     'question_name': 'question_1',
  //     'question_label': 'Is the fridge operating between 0-5°C?'
  //   }
  // ],

  // question_2: radio, hasAttachments
  'question_2': 'Yes',
  // 'question_2_attachments': [
  //   {
  //     'fileName': 'freezer_photo.jpg',
  //     'fileType': 'image',
  //     'file': null,
  //     'question_name': 'question_2',
  //     'question_label': 'Is the freezer operating below -18°C?'
  //   }
  // ],

  // question_3: radio, hasAttachments
  'question_3': 8,

  // question_4: radio, hasAttachments
  'question_4': 88,

  // question_5: number
  'question_5': 12,

  // question_6: text, hasAttachments
  'question_6': 'Found minor issue with door seal.',
  // 'question_6_attachments': [
  //   {
  //     'fileName': 'issue_photo.png',
  //     'fileType': 'image',
  //     'file': null,
  //     'question_name': 'question_6',
  //     'question_label': 'If an issue was found, describe the problem.'
  //   }
  // ],

  // question_7: radio, hasAttachments
  'question_7': 'No',
  'question_7_attachments': [
    {
      "file_url":
          'http://checklist-epic.petcaretechnologies.com/api/calendar/checklist-epic/calendar/aed065e6-76f7-40bd-b696-24ece8c31148.jpg'
    }
  ],

  // question_8: number
  'question_8': 88,
};
