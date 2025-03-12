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
    "name": "health_conditions",
    "type": "multiselect",
    "required": true,
    "label": "Select all health conditions that apply",
    "options": ["Diabetes", "Heart Disease", "Asthma", "High Blood Pressure", "Other"],
    "showWhen": {
      "has_health_issues": "Yes",
    }
  },
  {
    "name": "other_health_condition",
    "type": "text",
    "label": "Please specify other health condition",
    "required": true,
    "showWhen": {
    "has_health_issues": "Yes",
    "health_conditions": ["Other"],
    // "required": true,
    }
  }
  // },
  // {
  //   "name": "medication",
  //   "type": "radio",
  //   "label": "Are you currently taking any medication?",
  //   "options": ["Yes", "No"],
  //   "showWhen": {
  //     "has_health_issues": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "medication_type",
  //   "type": "multiselect",
  //   "label": "What type of medications are you taking?",
  //   "options": ["Pain Relief", "Blood Pressure", "Diabetes", "Heart", "Other"],
  //   "showWhen": {
  //     "has_health_issues": "Yes",
  //     "medication": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "medication_frequency",
  //   "type": "radio",
  //   "label": "How often do you take your medication?",
  //   "options": ["Daily", "Weekly", "Monthly", "As needed"],
  //   "showWhen": {
  //     "medication": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "allergies",
  //   "type": "radio",
  //   "label": "Do you have any allergies?",
  //   "options": ["Yes", "No"],
  //   "validators": ["required"],
  // },
  // {
  //   "name": "allergy_types",
  //   "type": "multiselect",
  //   "label": "Select all allergies that apply",
  //   "options": ["Food", "Medicine", "Environmental", "Other"],
  //   "showWhen": {
  //     "allergies": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "food_allergies",
  //   "type": "multiselect",
  //   "label": "Select your food allergies",
  //   "options": ["Nuts", "Dairy", "Eggs", "Shellfish", "Wheat", "Other"],
  //   "showWhen": {
  //     "allergies": "Yes",
  //     "allergy_types": ["Food"],
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "carries_epipen",
  //   "type": "radio",
  //   "label": "Do you carry an EpiPen?",
  //   "options": ["Yes", "No"],
  //   "showWhen": {
  //     "allergies": "Yes",
  //     "allergy_types": ["Food", "Medicine"],
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "exercise",
  //   "type": "radio",
  //   "label": "Do you exercise regularly?",
  //   "options": ["Yes", "No"],
  //   "validators": ["required"],
  // },
  // {
  //   "name": "exercise_frequency",
  //   "type": "radio",
  //   "label": "How often do you exercise?",
  //   "options": ["Daily", "2-3 times a week", "Weekly", "Monthly"],
  //   "showWhen": {
  //     "exercise": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "exercise_types",
  //   "type": "multiselect",
  //   "label": "What types of exercise do you do?",
  //   "options": ["Walking", "Running", "Swimming", "Cycling", "Gym", "Sports", "Other"],
  //   "showWhen": {
  //     "exercise": "Yes",
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "health_goals",
  //   "type": "multiselect",
  //   "label": "What are your health goals?",
  //   "options": ["Weight Loss", "Muscle Gain", "Better Sleep", "More Energy", "Stress Reduction", "Other"],
  //   "validators": ["required"],
  // },
  // {
  //   "name": "contact_preference",
  //   "type": "radio",
  //   "label": "Preferred method of contact",
  //   "options": ["Email", "Phone", "Both"],
  //   "validators": ["required"],
  // },
  // {
  //   "name": "email",
  //   "type": "text",
  //   "label": "Email address",
  //   "showWhen": {
  //     "contact_preference": ["Email", "Both"],
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "phone",
  //   "type": "text",
  //   "label": "Phone number",
  //   "showWhen": {
  //     "contact_preference": ["Phone", "Both"],
  //   "validators": ["required"],
  //   }
  // },
  // {
  //   "name": "additional_comments",
  //   "type": "text",
  //   "label": "Any additional comments or concerns?",
  //   "validators": ["required"],
  // }
];