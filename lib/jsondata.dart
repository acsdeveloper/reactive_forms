final List<Map<String, dynamic>> formJson = [
  {
    "name": "name",
    "type": "text",
    "label": "What is your name?",
    "required": true,
  },
  {
    "name": "age",
    "type": "number",
    "label": "What is your age?",
    "required": true,
    "min": 18,
    "max": 100
  },
  {
    "name": "has_health_issues",
    "type": "radio",
    "label": "Do you have any health issues?",
    "options": ["Yes", "No"],
    "required": true,
  },
  {
    "name": "health_type",
    "type": "radio",
    "label": "What type of health issue do you have?",
    "options": ["Diabetes", "Heart Disease", "Other"],
    "required": true,
   
  },
  {
    "name": "other_condition",
    "type": "text",
    "label": "Please specify your other health condition",
    "required": true,
    "showWhen": {
      "has_health_issues": "Yes",
      "health_type": "Other"
    },
  },
 {
    "name": "other_condition",
    "type": "text",
    "label": "Please specify your haRT health condition",
    "required": true,
    "showWhen": {
      "has_health_issues": "Yes",
      "health_type": "Heart Disease"
    }
  }
];
 
 