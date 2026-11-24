// Lists and the 44 starting documents, copied from supabase/seed.sql (used by demo mode only).
export const SEED = {
 "departments": [
  {
   "code": "GOV",
   "name": "Governance"
  },
  {
   "code": "QMS",
   "name": "QMS"
  },
  {
   "code": "OPS",
   "name": "Operations"
  },
  {
   "code": "TD",
   "name": "Training and Development"
  },
  {
   "code": "SG",
   "name": "Sustainability and Growth"
  },
  {
   "code": "ME",
   "name": "M&E (outsourced)"
  },
  {
   "code": "REP",
   "name": "Reports"
  },
  {
   "code": "FIN",
   "name": "Finance"
  },
  {
   "code": "HR",
   "name": "Human Resources"
  },
  {
   "code": "PR",
   "name": "Marketing and PR"
  },
  {
   "code": "EXE",
   "name": "Executive"
  }
 ],
 "processes": [
  {
   "code": "GOV-01",
   "name": "Policy Development and Approval",
   "department": "GOV"
  },
  {
   "code": "GOV-02",
   "name": "Risk Management",
   "department": "GOV"
  },
  {
   "code": "GOV-03",
   "name": "Board Reporting",
   "department": "GOV"
  },
  {
   "code": "GOV-04",
   "name": "Annual Planning and Budgeting",
   "department": "GOV"
  },
  {
   "code": "GOV-05",
   "name": "Communication (proposed)",
   "department": "GOV"
  },
  {
   "code": "QMS-01",
   "name": "Document Control",
   "department": "QMS"
  },
  {
   "code": "QMS-02",
   "name": "Internal Audit",
   "department": "QMS"
  },
  {
   "code": "QMS-03",
   "name": "Continuous Improvement",
   "department": "QMS"
  },
  {
   "code": "QMS-04",
   "name": "Client Reporting Quality Review",
   "department": "QMS"
  },
  {
   "code": "QMS-05",
   "name": "Asset Management",
   "department": "QMS"
  },
  {
   "code": "OPS-01",
   "name": "Project Start-Up",
   "department": "OPS"
  },
  {
   "code": "OPS-02",
   "name": "Project Tracking",
   "department": "OPS"
  },
  {
   "code": "OPS-03",
   "name": "Project Closure",
   "department": "OPS"
  },
  {
   "code": "T&D-01",
   "name": "Beneficiary Journey",
   "department": "TD"
  },
  {
   "code": "T&D-02",
   "name": "Mentor Management",
   "department": "TD"
  },
  {
   "code": "T&D-03",
   "name": "Training Delivery",
   "department": "TD"
  },
  {
   "code": "SG-01",
   "name": "Opportunity Management",
   "department": "SG"
  },
  {
   "code": "SG-02",
   "name": "Client Handover",
   "department": "SG"
  },
  {
   "code": "SG-03",
   "name": "Marketing",
   "department": "SG"
  },
  {
   "code": "M&E-01",
   "name": "Framework Development",
   "department": "ME"
  },
  {
   "code": "M&E-02",
   "name": "Quarterly Monitoring",
   "department": "ME"
  },
  {
   "code": "M&E-03",
   "name": "Reporting: mentor quarterly programme reports",
   "department": "REP"
  },
  {
   "code": "FIN-01",
   "name": "Payment Request (PR)",
   "department": "FIN"
  },
  {
   "code": "FIN-02",
   "name": "Asset Payment Request (APR)",
   "department": "FIN"
  },
  {
   "code": "FIN-03",
   "name": "Operational Payment Request (OPR)",
   "department": "FIN"
  },
  {
   "code": "FIN-04",
   "name": "Internship Payment Request (IPR)",
   "department": "FIN"
  },
  {
   "code": "FIN-05",
   "name": "Bursary Payment Request (BPR)",
   "department": "FIN"
  },
  {
   "code": "FIN-06",
   "name": "Donations and Section 18A Receipts (proposed)",
   "department": "FIN"
  },
  {
   "code": "FIN-07",
   "name": "Procurement",
   "department": "FIN"
  },
  {
   "code": "FIN-08",
   "name": "Internship Travel (ITV)",
   "department": "FIN"
  },
  {
   "code": "FIN-09",
   "name": "Bursary Travel (BTV)",
   "department": "FIN"
  },
  {
   "code": "FIN-10",
   "name": "Internal Travel (TVT)",
   "department": "FIN"
  },
  {
   "code": "FIN-11",
   "name": "Payroll",
   "department": "FIN"
  },
  {
   "code": "FIN-12",
   "name": "Tax Compliance (VAT and PBO) (proposed)",
   "department": "FIN"
  },
  {
   "code": "HR-01",
   "name": "Recruitment",
   "department": "HR"
  },
  {
   "code": "HR-02",
   "name": "Onboarding",
   "department": "HR"
  },
  {
   "code": "HR-03",
   "name": "Performance Management",
   "department": "HR"
  },
  {
   "code": "HR-04",
   "name": "Remote Work",
   "department": "HR"
  },
  {
   "code": "HR-05",
   "name": "Offboarding",
   "department": "HR"
  }
 ],
 "documents": [
  {
   "code": null,
   "previous_code": "QMS-05",
   "title": "Asset Management Procedure",
   "doc_type": "SOP",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-01",
   "title": "Asset Purchase Request",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-02",
   "title": "Equipment Issue and Acknowledgement",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-03",
   "title": "Asset Return and Internal Transfer",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-04",
   "title": "Loss, Theft and Damage Report",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-05",
   "title": "Donation Received Record",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-06",
   "title": "Asset Donation or Transfer Certificate",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-07",
   "title": "Store Booking, Check-out and Return",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-FRM-08",
   "title": "Device Preparation and Pre-handover Check",
   "doc_type": "FRM",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-GUI-01",
   "title": "Staff Guide",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-GUI-02",
   "title": "Factotum Guide",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-GUI-03",
   "title": "Asset Coordinator Guide",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-GUI-04",
   "title": "Management Guide",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-GUI-05",
   "title": "Department Asset Contact Guide",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": null,
   "previous_code": "QMS-05-WF-01",
   "title": "Asset Management Workflows",
   "doc_type": "MAP",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-GUI-GOV-001",
   "previous_code": null,
   "title": "Staff Guide Document Control and QMS Management",
   "doc_type": "GUI",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-GUI-OPS-001",
   "previous_code": null,
   "title": "Staff Guide Travel Hub",
   "doc_type": "GUI",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-MAN-GOV-001",
   "previous_code": null,
   "title": "Quality Management System Manual",
   "doc_type": "MAN",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": true,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-MAP-GOV-001",
   "previous_code": null,
   "title": "Process Map Register",
   "doc_type": "MAP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-POL-FIN-002",
   "previous_code": null,
   "title": "Travel and Subsistence Policy",
   "doc_type": "POL",
   "domain": "FIN",
   "department": "FIN",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-POL-FIN-003",
   "previous_code": null,
   "title": "Asset Management Policy",
   "doc_type": "POL",
   "domain": "FIN",
   "department": "FIN",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-POL-GOV-007",
   "previous_code": null,
   "title": "Code of Ethics and Conduct",
   "doc_type": "POL",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": true,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-POL-GOV-008",
   "previous_code": null,
   "title": "Anti-Fraud Bribery and Corruption Policy",
   "doc_type": "POL",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": true,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-POL-INF-003",
   "previous_code": null,
   "title": "Records Retention and Destruction Policy",
   "doc_type": "POL",
   "domain": "INF",
   "department": "QMS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-COM-001",
   "previous_code": null,
   "title": "Compliance Obligations Register",
   "doc_type": "REG",
   "domain": "COM",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-GOV-008",
   "previous_code": null,
   "title": "Context and Interested Parties Register",
   "doc_type": "REG",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-GOV-009",
   "previous_code": null,
   "title": "Quality Objectives and KPI Plan",
   "doc_type": "REG",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-GOV-010",
   "previous_code": null,
   "title": "Internal Audit Programme and Stage 1 Readiness",
   "doc_type": "REG",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-GOV-011",
   "previous_code": null,
   "title": "Risk Incident and Corrective Action Register",
   "doc_type": "REG",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-REG-INF-003",
   "previous_code": null,
   "title": "Systems and Operator Inventory",
   "doc_type": "REG",
   "domain": "INF",
   "department": "QMS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-COM-008",
   "previous_code": null,
   "title": "NPO Act Statutory Compliance Procedure",
   "doc_type": "SOP",
   "domain": "COM",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-COM-009",
   "previous_code": null,
   "title": "Terrorist-Financing Risk and Partner Due Diligence Procedure",
   "doc_type": "SOP",
   "domain": "COM",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-FIN-006",
   "previous_code": null,
   "title": "Donations and Section 18A Receipts Procedure",
   "doc_type": "SOP",
   "domain": "FIN",
   "department": "FIN",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-FIN-007",
   "previous_code": null,
   "title": "VAT Compliance Procedure",
   "doc_type": "SOP",
   "domain": "FIN",
   "department": "FIN",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-FIN-008",
   "previous_code": null,
   "title": "Payroll Administration and Statutory Compliance Procedure",
   "doc_type": "SOP",
   "domain": "FIN",
   "department": "FIN",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-001",
   "previous_code": null,
   "title": "Document Control Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-006",
   "previous_code": null,
   "title": "Complaints and Feedback Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-007",
   "previous_code": null,
   "title": "Client Report Quality Review Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-008",
   "previous_code": null,
   "title": "Programme Design and Development Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-009",
   "previous_code": null,
   "title": "Communication Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-010",
   "previous_code": null,
   "title": "Change Management Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-011",
   "previous_code": null,
   "title": "Client and Beneficiary Satisfaction Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-GOV-012",
   "previous_code": null,
   "title": "Knowledge Management Procedure",
   "doc_type": "SOP",
   "domain": "GOV",
   "department": "GOV",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  },
  {
   "code": "QMS-SOP-OPS-001",
   "previous_code": null,
   "title": "Client-Funded Programme Evidence Control Procedure",
   "doc_type": "SOP",
   "domain": "OPS",
   "department": "OPS",
   "is_governance": false,
   "owner_role": "Operations and Programme Systems Coordinator (QMS Administrator)"
  }
 ]
};
