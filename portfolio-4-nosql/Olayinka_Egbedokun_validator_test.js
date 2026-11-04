// Wavers University — Portfolio 4: the validator must reject bad documents.
// Two inserts, each breaking exactly one rule (every other field is valid),
// so each rejection can only come from that rule. Valid documents are shown
// to be accepted by the import itself.
function attempt(label, grade, score) {
  try {
    db.student_records.insertOne({
      _id: "WU/2099/0001", name: { first: "Test", last: "Student" }, programme: "CSC-BSC", status: "active",
      unitsTaken: NumberInt(3), unitsPassed: NumberInt(3), cgpa: NumberDecimal("5.00"),
      semesters: [{ session: "2099/2100", term: "first", unitsTaken: NumberInt(3), gpa: NumberDecimal("5.00"),
        courses: [{ code: "CSC101", title: "Test", units: NumberInt(3), score: NumberDecimal(score), grade: grade,
                    points: NumberInt(5), amended: false }] }]
    });
    print(label + ": ACCEPTED (the validator did not stop it)");
    db.student_records.deleteOne({ _id: "WU/2099/0001" });
  } catch (e) {
    print(label + ": REJECTED: code " + e.code + " (" + e.errmsg + ")");
  }
}
attempt("grade G, score 75.00", "G", "75.00");
attempt("grade A, score 120.00", "A", "120.00");
