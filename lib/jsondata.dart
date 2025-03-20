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
    "type": "radio",
    "label": "Was the temperature checked twice today (AM & PM)?",
    "options": ["Yes", "No"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": false,
    "showWhen": {
      "question_1": ["C1"]
    }
  },
  {
    "name": "question_4",
    "type": "radio",
    "label": "Was the jelly pot or thermometer used to check the temperature?",
    "options": ["Yes", "No"],
    "required": true,
    "hasAttachments": true,
    "showWhen": {
      "question_1": ["B1"]
    }
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
    "hasAttachments": false
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
