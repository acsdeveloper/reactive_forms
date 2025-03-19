final List<Map<String, dynamic>> formJson = [
  {
    "name": "question_1",
    "type": "radio",
    "label": "Is the fridge operating between 0-5°C?",
    "options": ["A1", "B1", "C1", "D1"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": false,
    "commentsRequired": false
  },
  {
    "name": "question_2",
    "type": "radio",
    "label": "Is the freezer operating below -18°C?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": false,
    "commentsRequired": false,
    "showWhen": {
      "question_1": ["A1", "D1"]
    }
  },
  {
    "name": "question_3",
    "type": "radio",
    "label": "Was the temperature checked twice today (AM & PM)?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": false,
    "commentsRequired": false,
    "showWhen": {
      "question_1": ["A1"],
      "question_2": ["NO"]
    }
  },
  {
    "name": "question_4",
    "type": "radio",
    "label": "Was the jelly pot or thermometer used to check the temperature?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": false,
    "commentsRequired": false
  }
];
 
 