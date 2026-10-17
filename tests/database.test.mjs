import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
test("Postgres RPCs enforce ownership, hidden keys, scoring, deadlines, idempotency and RLS", async () => {
  const db = new PGlite();
  await db.exec(
    `create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key); create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; grant usage on schema auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`,
  );
  const migrations = new URL('../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(name => name.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(file, migrations), 'utf8'));
  }
  const teacher = "11111111-1111-4111-8111-111111111111",
    student = "22222222-2222-4222-8222-222222222222",
    other = "33333333-3333-4333-8333-333333333333";
  await db.query("insert into auth.users values ($1),($2),($3)", [
    teacher,
    student,
    other,
  ]);
  await db.query("insert into public.teachers values ($1)", [teacher]);
  async function as(id) {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
    await db.exec("set role authenticated");
  }
  async function rpc(name, params = []) {
    return (
      await db.query(
        `select public.${name}(${params.map((_, i) => "$" + (i + 1)).join(",")}) as result`,
        params,
      )
    ).rows[0].result;
  }
  await as(student);
  await assert.rejects(
    rpc("create_quiz", ["Bad", "native", 60, 2, null, "[]"]),
    /teacher/,
  );
  await as(teacher);
  const id = await rpc("create_quiz", [
    "Math",
    "native",
    60,
    2,
    null,
    JSON.stringify([
      { prompt: "2+2?", options: ["3", "4"], correct: 1 },
      { prompt: "1+1?", options: ["2", "3"], correct: 0 },
    ]),
  ]);
  const code = (await db.query("select code from quizzes where id=$1", [id]))
    .rows[0].code;
  await as(student);
  await assert.rejects(rpc("start_attempt", [code]), /not found/);
  await as(teacher);
  await rpc("publish_quiz", [id]);
  await as(student);
  const a = await rpc("start_attempt", [code]);
  assert.equal(JSON.stringify(a).includes("correct"), false);
  assert.equal((await db.query("select * from questions")).rows.length, 0);
  assert.equal((await db.query("select * from quizzes")).rows.length, 0);
  await assert.rejects(
    db.query("update attempts set score=100"),
    /permission denied/,
  );
  await assert.rejects(
    db.query("insert into teachers values ($1)", [student]),
    /permission denied/,
  );
  await assert.rejects(
    db.query("select private.payload($1)", [a.id]),
    /permission denied/,
  );
  await assert.rejects(
    rpc("save_answer", [a.id, a.questions[0].id, 8]),
    /Invalid answer/,
  );
  await rpc("save_answer", [a.id, a.questions[0].id, 1]);
  await as(other);
  await assert.rejects(rpc("finish_attempt", [a.id]), /not found/);
  assert.equal((await db.query("select * from attempts")).rows.length, 0);
  await as(student);
  let result = await rpc("finish_attempt", [a.id]);
  assert.equal(result.score, 1);
  assert.equal(result.status, "submitted");
  result = await rpc("save_answer", [a.id, a.questions[1].id, 0]);
  assert.equal(result.score, 1);
  assert.equal((await rpc("start_attempt", [code])).id, a.id);
  await as(other);
  const b = await rpc("start_attempt", [code]);
  const event = "44444444-4444-4444-8444-444444444444";
  await rpc("report_violation", [b.id, event]);
  result = await rpc("report_violation", [b.id, event]);
  assert.equal(result.violations, 1);
  result = await rpc("report_violation", [
    b.id,
    "55555555-5555-4555-8555-555555555555",
  ]);
  assert.equal(result.status, "flagged");
  assert.equal(result.violations, 2);
  await as(teacher);
  assert.equal((await db.query("select * from violations")).rows.length, 2);
  assert.equal((await db.query("select * from attempts")).rows.length, 2);
  const form = await rpc("create_quiz", [
    "Form",
    "google",
    60,
    2,
    "https://forms.gle/abc",
    "[]",
  ]);
  await rpc("publish_quiz", [form]);
  const formCode = (
    await db.query("select code from quizzes where id=$1", [form])
  ).rows[0].code;
  await assert.rejects(
    rpc("create_quiz", [
      "Phishing",
      "google",
      60,
      2,
      "https://forms.gle.evil.test/abc",
      "[]",
    ]),
    /share URL/,
  );
  await as(student);
  const c = await rpc("start_attempt", [formCode]);
  result = await rpc("finish_attempt", [c.id]);
  assert.equal(result.score, null);
  assert.equal(result.status, "ended");
  await as(other);
  const d = await rpc("start_attempt", [formCode]);
  await db.exec("reset role");
  await db.query(
    "update attempts set deadline=now()-interval '1 second' where id=$1",
    [d.id],
  );
  await as(other);
  result = await rpc("start_attempt", [formCode]);
  assert.equal(result.status, "expired");
  await db.exec("reset role; set role anon");
  await assert.rejects(
    db.query("select * from questions"),
    /permission denied/,
  );
  await assert.rejects(rpc("start_attempt", [code]), /permission denied/);
  await db.close();
});
