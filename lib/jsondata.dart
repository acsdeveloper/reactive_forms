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
  },
  {
    "name": "question_5",
    "type": "radio",
    "label": "Is the fridge temperature within the recommended range for food safety?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": true,
    "commentsRequired": true,
    "showWhen": {
      "question_2": ["YES"]
    }
  },
  {
    "name": "question_6",
    "type": "radio",
    "label": "Are there any abnormalities in the freezer operation?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": true,
    "commentsRequired": true,
    "showWhen": {
      "question_2": ["YES"]
    }
  },
  {
    "name": "question_7",
    "type": "radio",
    "label": "Did the temperature check indicate that the fridge is too cold?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": true,
    "commentsRequired": false,
    "showWhen": {
      "question_3": ["YES"]
    }
  },
  {
    "name": "question_8",
    "type": "radio",
    "label": "Is there a need to increase the fridge temperature?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": true,
    "commentsRequired": false,
    "showWhen": {
      "question_7": ["YES"]
    }
  },
  {
    "name": "question_9",
    "type": "radio",
    "label": "Is the freezer temperature too low, requiring adjustments?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": [],
    "disableAttachmentsOn": [],
    "hasComments": true,
    "commentsRequired": false,
    "showWhen": {
      "question_6": ["YES"]
    }
  },
  {
    "name": "question_10",
    "type": "radio",
    "label": "Was there any issue during the temperature checks?",
    "options": ["YES", "NO"],
    "required": true,
    "hasAttachments": true,
    "requireAttachmentsOn": ["YES"],
    "disableAttachmentsOn": ["NO"],
    "hasComments": true,
    "commentsRequired": true,
    "showWhen": {
      "question_4": ["YES"]
    }
  }
];
