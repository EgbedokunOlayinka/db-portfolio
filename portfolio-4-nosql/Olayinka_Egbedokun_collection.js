// Wavers University — Portfolio 4: the student_records collection and its validator
//
// One document per student: the whole academic record, as the portal shows
// it. The $jsonSchema validator rejects any document whose shape or values
// break the rules below, the document-store counterpart of Portfolio 1's
// CHECK constraints.

db.student_records.drop();
db.createCollection("student_records", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "name", "programme", "status", "semesters", "unitsTaken", "unitsPassed", "cgpa"],
    properties: {
      _id:       { bsonType: "string", pattern: "^WU/[0-9]{4}/[0-9]{4}$", description: "matric number" },
      name:      { bsonType: "object", required: ["first", "last"],
                   properties: { first: { bsonType: "string", minLength: 1 }, last: { bsonType: "string", minLength: 1 } } },
      programme: { bsonType: "string" },
      status:    { enum: ["active", "suspended", "withdrawn", "graduated"] },
      unitsTaken:  { bsonType: "int", minimum: 0 },
      unitsPassed: { bsonType: "int", minimum: 0 },
      cgpa:      { bsonType: ["decimal", "null"], minimum: 0, maximum: 5 },
      semesters: { bsonType: "array", items: {
        bsonType: "object", required: ["session", "term", "unitsTaken", "gpa", "courses"],
        properties: {
          session:    { bsonType: "string", pattern: "^[0-9]{4}/[0-9]{4}$" },
          term:       { enum: ["first", "second"] },
          unitsTaken: { bsonType: "int", minimum: 1 },
          gpa:        { bsonType: "decimal", minimum: 0, maximum: 5 },
          courses:    { bsonType: "array", minItems: 1, items: {
            bsonType: "object", required: ["code", "title", "units", "score", "grade", "points", "amended"],
            properties: {
              code:    { bsonType: "string", pattern: "^[A-Z]{3}[1-5][0-9]{2}$" },
              title:   { bsonType: "string" },
              units:   { bsonType: "int", minimum: 1, maximum: 6 },
              score:   { bsonType: "decimal", minimum: 0, maximum: 100 },
              grade:   { enum: ["A", "B", "C", "D", "E", "F"] },
              points:  { bsonType: "int", minimum: 0, maximum: 5 },
              amended: { bsonType: "bool" } } } } } } } } } },
  validationLevel: "strict",
  validationAction: "error"
});
print("student_records created with its validator");
