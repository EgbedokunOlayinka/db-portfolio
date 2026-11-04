// Wavers University — Portfolio 4: indexes for M2 and M3
//   M2: programme first (equality), then cgpa descending and _id: the
//       dean's list is read from the index already in order, 10 entries.
//   M3: a multikey index: one entry per embedded course, on (code, grade),
//       so "failed CSC211" goes straight to the matching students.
db.student_records.createIndex({ programme: 1, cgpa: -1, _id: 1 }, { name: "programme_cgpa" });
db.student_records.createIndex({ "semesters.courses.code": 1, "semesters.courses.grade": 1 }, { name: "course_grade" });
printjson(db.student_records.getIndexes().map(i => i.name));
