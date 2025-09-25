final List<Map<String, dynamic>> formJson = [
  {
    "name": "question_1",
    "type": "dropdown",
    "label": "Fridge number or name ",
    "options": [
      "Walk in Fridge 1",
      "Drinks Fridge 2",
      "Drinks Fridge 3",
      "Drinks Fridge 4",
      "UC Fridge 5",
      "UC Fridge 6",
      "UC Fridge 7",
      "BOH Milk Fridge 8"
    ],
    "required": false,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
  },
  {
    "name": "question_2",
    "type": "temp",
    "label": "Temperature in degree C?",
    "options": [],
    "required": true,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
    "groupId": "question_1",
    "min": -30.0,
    "max": 130.0,
    "step": 0.1,
    "unit": "°C"
  },
  {
    "name": "question_3",
    "type": "radio",
    "label": "Initials of person completing the check ",
    "options": ["RT", "Other"],
    "required": true,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
    "groupId": "question_1"
  },
  {
    "name": "question_4",
    "type": "text",
    "label": "Initials of person completing the check if other ",
    "options": [],
    "required": true,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
    "showWhen": {"question_3": "Other"},
  },
  {
    "name": "question_5",
    "type": "radio",
    "label": "Fridge temperature within permissible limits of 1-5 degree C?",
    "options": ["Yes", "No"],
    "required": true,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
  },
  {
    "name": "question_6",
    "type": "text",
    "label":
        "Corrective action taken if temperature outside of permissible limits ",
    "options": [],
    "required": true,
    "hasAttachments": false,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false,
    "showWhen": {"question_4": "No"},
  }
];

/// Sample initial values for autofill demonstration
final Map<String, dynamic> sampleInitialValues = {
  // question_1: radio, hasAttachments
  'question_1': 'A1',
  'question_1_comment': 'This is a comment for question 1',
  'question_1_attachments': [
    {
      'file_url':
          'http://checklist-epic.petcaretechnologies.com/api/calendar/checklist-epic/calendar/be114cec-3ac0-440e-bf59-82d34bdaf6dd.jpg',
      'question_name': 'question_1',
      'question_label': 'Is the fridge operating between 0-5°C?'
    }
  ],

  // question_2: radio, hasAttachments
  'question_2': 'Yes',
  'question_2_attachments': [
    {
      'file_url':
          'http://checklist-epic.petcaretechnologies.com/api/calendar/checklist-epic/calendar/a067fcc7-e156-449a-9c7a-3f682cbf262e.pdf',
      'question_name': 'question_2',
      'question_label': 'Is the freezer operating below -18°C?'
    }
  ],

  // question_3: radio, hasAttachments
  'question_3': 8,

  // question_4: radio, hasAttachments
  'question_4': 88,

  // question_5: number
  'question_5': 12,

  // question_6: text, hasAttachments
  'question_6': 'Found minor issue with door seal.',
  'question_6_attachments': [
    {
      'file_url':
          'http://checklist-epic.petcaretechnologies.com/api/calendar/checklist-epic/calendar/5fa00635-1e6a-4978-9282-cdb6bdca1d98.jpeg',
      'question_name': 'question_6',
      'question_label': 'If an issue was found, describe the problem.'
    }
  ],

  // question_7: radio, hasAttachments
  'question_7': 'No',
  'question_7_attachments': [
    {
      'file_url':
          'http://checklist-epic.petcaretechnologies.com/api/calendar/checklist-epic/calendar/5fa00635-1e6a-4978-9282-cdb6bdca1d98.jpeg',
      'question_name': 'question_7',
      'question_label': 'Were corrective actions taken to resolve the issue?'
    }
  ],

  // question_8: number
  'question_8': 88,
};
