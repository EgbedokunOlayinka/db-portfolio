// Wavers University — Portfolio 4: the MongoDB queries M1-M4
//
// Run by the reproduce script with a parameter object P defined first:
//   P = { matric, programme, course }
// Each section prints one line per result, in the same format as the
// PostgreSQL answer to the same question (Olayinka_Egbedokun_pg_answers.sql),
// so the two can be compared line by line.

// M1: one student's transcript: a single document, read by its key.
print("=== M1 transcript");
const rec = db.student_records.findOne({ _id: P.matric });
rec.semesters.forEach(s => s.courses.forEach(c =>
  print([s.session, s.term, c.code, c.score.toString(), c.grade].join("|"))));

// M2: dean's list: top 10 CGPAs in one programme.
print("=== M2 dean's list");
db.student_records.find({ programme: P.programme }, { cgpa: 1 })
  .sort({ cgpa: -1, _id: 1 }).limit(10)
  .forEach(d => print(d._id + "|" + d.cgpa.toString()));

// M3: everyone who failed a course: a condition on one embedded course.
// $elemMatch makes both conditions apply to the SAME course entry.
print("=== M3 failed " + P.course);
db.student_records.find(
    { "semesters.courses": { $elemMatch: { code: P.course, grade: "F" } } }, { _id: 1 })
  .sort({ _id: 1 }).forEach(d => print(d._id));

// M4: every student's totals recomputed from the embedded courses: quality
// points (grade points x units) and units. CGPA = points / units.
print("=== M4 totals");
db.student_records.aggregate([
  { $unwind: "$semesters" },
  { $unwind: "$semesters.courses" },
  { $group: { _id: "$_id",
              points: { $sum: { $multiply: ["$semesters.courses.points", "$semesters.courses.units"] } },
              units:  { $sum: "$semesters.courses.units" } } },
  { $sort: { _id: 1 } }
]).forEach(d => print(d._id + "|" + d.points + "|" + d.units));

print("=== M4 stored cgpa");
db.student_records.find({}, { cgpa: 1 }).sort({ _id: 1 })
  .forEach(d => print(d._id + "|" + (d.cgpa === null ? "" : d.cgpa.toString())));
