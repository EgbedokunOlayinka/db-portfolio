// Wavers University — Portfolio 4: how M2 and M3 run, without and with indexes
//
// explain("executionStats") reports the winning plan and how many index
// keys and documents the query examined. Run once before the indexes exist
// and once after (P.phase says which).

function stages(plan) {            // the plan's stages, outermost first
  const out = [];
  for (let p = plan; p; p = p.inputStage || (p.inputStages && p.inputStages[0])) out.push(p.stage + (p.indexName ? "(" + p.indexName + ")" : ""));
  return out.join(" <- ");
}
function report(label, cursor) {
  const e = cursor.explain("executionStats");
  const s = e.executionStats;
  print(label + " " + P.phase + "|docsExamined=" + s.totalDocsExamined + "|keysExamined=" + s.totalKeysExamined +
        "|returned=" + s.nReturned + "|plan=" + stages(e.queryPlanner.winningPlan));
}
report("M2", db.student_records.find({ programme: P.programme }, { cgpa: 1 }).sort({ cgpa: -1, _id: 1 }).limit(10));
report("M3", db.student_records.find({ "semesters.courses": { $elemMatch: { code: P.course, grade: "F" } } }, { _id: 1 }).sort({ _id: 1 }));
