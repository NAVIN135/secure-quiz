"use client";
import { useEffect, useState } from "react";
import { db } from "../lib/client";
type Quiz = {
  id: string;
  title: string;
  code: string;
  mode: string;
  published: boolean;
  duration_seconds: number;
};
type Attempt = {
  id: string;
  student_id: string;
  status: string;
  score: number | null;
  max_score: number;
  violations: number;
  started_at: string;
};
type Question = { prompt: string; options: string[]; correct: number };
export default function Page() {
  const [email, E] = useState(""),
    [password, P] = useState(""),
    [user, U] = useState(""),
    [message, M] = useState(""),
    [busy, B] = useState(false);
  const [quizzes, Q] = useState<Quiz[]>([]),
    [selected, S] = useState<Quiz | null>(null),
    [attempts, A] = useState<Attempt[]>([]);
  const [title, T] = useState(""),
    [mode, K] = useState("native"),
    [minutes, D] = useState(10),
    [limit, L] = useState(3),
    [url, F] = useState("");
  const [questions, J] = useState<Question[]>([
    { prompt: "", options: ["", "", "", ""], correct: 0 },
  ]);
  const [events, V] = useState<{ kind: string; created_at: string }[]>([]);
  async function run(action: () => Promise<void>) {
    B(true);
    M("");
    try {
      await action();
    } catch (e) {
      M(e instanceof Error ? e.message : String(e));
    } finally {
      B(false);
    }
  }
  async function load() {
    if (!db) return;
    const r = await db
      .from("quizzes")
      .select("*")
      .order("created_at", { ascending: false });
    if (r.error) throw r.error;
    Q(r.data || []);
  }
  useEffect(() => {
    if (!db) return;
    db.auth.getSession().then(({ data }) => U(data.session?.user.email || ""));
    const { data } = db.auth.onAuthStateChange((_event, session) =>
      U(session?.user.email || ""),
    );
    return () => data.subscription.unsubscribe();
  }, []);
  useEffect(() => {
    if (user) void run(load);
  }, [user]);
  async function review(q: Quiz) {
    S(q);
    V([]);
    const r = await db!
      .from("attempts")
      .select("id,student_id,status,score,max_score,violations,started_at")
      .eq("quiz_id", q.id)
      .order("started_at", { ascending: false });
    if (r.error) throw r.error;
    A(r.data || []);
  }
  function update(i: number, patch: Partial<Question>) {
    J(questions.map((q, n) => (n === i ? { ...q, ...patch } : q)));
  }
  return (
    <main>
      <header>
        <a className="brand" href="/">
          SQ<span>SecureQuiz</span>
        </a>
        <span className="badge">TEACHER WORKSPACE</span>
        {user && (
          <button
            onClick={() =>
              void run(async () => {
                await db!.auth.signOut();
                Q([]);
                S(null);
              })
            }
          >
            Sign out
          </button>
        )}
      </header>
      <section className="intro">
        <p className="eyebrow">ASSESS WITH CLARITY</p>
        <h1>
          Your classroom.
          <br />
          <em>A clearer picture.</em>
        </h1>
        <p>
          Create timed quizzes, share a join code, and review results and
          reported app switches in one place.
        </p>
      </section>
      {!db ? (
        <section className="card">
          <h2>Connect your workspace</h2>
          <p>
            The dashboard is running. Add the Supabase project URL and public
            key using the included setup guide to enable sign-in and quizzes.
          </p>
          <p>No service-role key belongs in this app.</p>
        </section>
      ) : !user ? (
        <form
          className="card login"
          onSubmit={(e) => {
            e.preventDefault();
            void run(async () => {
              const r = await db!.auth.signInWithPassword({ email, password });
              if (r.error) throw r.error;
            });
          }}
        >
          <h2>Welcome back</h2>
          <p>Sign in with your approved teacher account.</p>
          <label>
            Email
            <input
              type="email"
              required
              value={email}
              onChange={(e) => E(e.target.value)}
            />
          </label>
          <label>
            Password
            <input
              type="password"
              required
              value={password}
              onChange={(e) => P(e.target.value)}
            />
          </label>
          <button className="primary" disabled={busy}>
            Sign in
          </button>
        </form>
      ) : (
        <div className="grid">
          <section className="card">
            <h2>Create a quiz</h2>
            <p>
              Published quizzes are locked to keep every attempt consistent.
            </p>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void run(async () => {
                  const r = await db!.rpc("create_quiz", {
                    p_title: title,
                    p_mode: mode,
                    p_duration: minutes * 60,
                    p_limit: limit,
                    p_url: mode === "native" ? null : url,
                    p_questions: mode === "native" ? questions : [],
                  });
                  if (r.error) throw r.error;
                  T("");
                  J([{ prompt: "", options: ["", "", "", ""], correct: 0 }]);
                  await load();
                  M("Draft created. Publish it when ready.");
                });
              }}
            >
              <label>
                Quiz title
                <input
                  required
                  maxLength={150}
                  value={title}
                  onChange={(e) => T(e.target.value)}
                />
              </label>
              <label>
                Mode
                <select value={mode} onChange={(e) => K(e.target.value)}>
                  <option value="native">
                    Native quiz · automatic scoring
                  </option>
                  <option value="google">Google Forms link</option>
                  <option value="microsoft">Microsoft Forms link</option>
                </select>
              </label>
              <div className="pair">
                <label>
                  Time (minutes)
                  <input
                    type="number"
                    min={1}
                    max={180}
                    required
                    value={minutes}
                    onChange={(e) => D(+e.target.value)}
                  />
                </label>
                <label>
                  Switch limit
                  <input
                    type="number"
                    min={1}
                    max={20}
                    required
                    value={limit}
                    onChange={(e) => L(+e.target.value)}
                  />
                </label>
              </div>
              {mode === "native" ? (
                <>
                  {questions.map((q, i) => (
                    <fieldset key={i}>
                      <legend>Question {i + 1}</legend>
                      <label>
                        Question
                        <input
                          required
                          maxLength={1000}
                          value={q.prompt}
                          onChange={(e) =>
                            update(i, { prompt: e.target.value })
                          }
                        />
                      </label>
                      {q.options.map((o, k) => (
                        <label key={k}>
                          Option {k + 1}
                          <input
                            required
                            maxLength={500}
                            value={o}
                            onChange={(e) =>
                              update(i, {
                                options: q.options.map((v, n) =>
                                  n === k ? e.target.value : v,
                                ),
                              })
                            }
                          />
                        </label>
                      ))}
                      <label>
                        Correct answer
                        <select
                          value={q.correct}
                          onChange={(e) =>
                            update(i, { correct: +e.target.value })
                          }
                        >
                          {q.options.map((_, k) => (
                            <option key={k} value={k}>
                              Option {k + 1}
                            </option>
                          ))}
                        </select>
                      </label>
                      {questions.length > 1 && (
                        <button
                          type="button"
                          onClick={() => J(questions.filter((_, n) => n !== i))}
                        >
                          Remove question
                        </button>
                      )}
                    </fieldset>
                  ))}
                  <button
                    type="button"
                    disabled={questions.length >= 100}
                    onClick={() =>
                      J([
                        ...questions,
                        { prompt: "", options: ["", "", "", ""], correct: 0 },
                      ])
                    }
                  >
                    + Add question
                  </button>
                </>
              ) : (
                <>
                  <label>
                    Form share URL
                    <input
                      type="url"
                      required
                      value={url}
                      onChange={(e) => F(e.target.value)}
                    />
                  </label>
                  <aside>
                    Forms open inside the Android app. Provider sign-in may need
                    a browser. SecureQuiz cannot verify submission, read
                    responses, or calculate a Forms score. Ending the session
                    does not submit or close the provider’s form. App-switch
                    reports are advisory.
                  </aside>
                </>
              )}
              <button disabled={busy} className="primary">
                Save draft
              </button>
            </form>
          </section>
          <section>
            <div className="card">
              <h2>
                Your quizzes <span className="count">{quizzes.length}</span>
              </h2>
              <button disabled={busy} onClick={() => void run(load)}>
                Refresh
              </button>
              {quizzes.length === 0 && (
                <p>
                  No quizzes yet. Your first quiz starts here. Only approved
                  teachers can create quizzes.
                </p>
              )}
              {quizzes.map((q) => (
                <article key={q.id}>
                  <div>
                    <h3>{q.title}</h3>
                    <p>
                      {q.mode} · {q.duration_seconds / 60} min ·{" "}
                      {q.published ? "Published" : "Draft"}
                    </p>
                    {q.published && (
                      <p>
                        Join code <strong className="code">{q.code}</strong>
                      </p>
                    )}
                  </div>
                  <div className="actions">
                    {!q.published && (
                      <button
                        onClick={() =>
                          void run(async () => {
                            const r = await db!.rpc("publish_quiz", {
                              p_quiz: q.id,
                            });
                            if (r.error) throw r.error;
                            await load();
                          })
                        }
                      >
                        Publish
                      </button>
                    )}
                    <button onClick={() => void run(() => review(q))}>
                      Results
                    </button>
                  </div>
                </article>
              ))}
            </div>
            {selected && (
              <div className="card results">
                <h2>{selected.title} · Results</h2>
                <p>
                  Student IDs identify accounts. Expired active sessions
                  finalize when the student reconnects. Refresh to see new
                  activity.
                </p>
                <button onClick={() => void run(() => review(selected))}>
                  Refresh results
                </button>
                <div className="table">
                  <table>
                    <thead>
                      <tr>
                        <th>Student</th>
                        <th>Status</th>
                        <th>Score</th>
                        <th>Switches</th>
                      </tr>
                    </thead>
                    <tbody>
                      {attempts.map((a) => (
                        <tr key={a.id}>
                          <td title={a.student_id}>
                            {a.student_id.slice(0, 8)}
                          </td>
                          <td>{a.status}</td>
                          <td>
                            {a.score === null
                              ? "—"
                              : `${a.score}/${a.max_score}`}
                          </td>
                          <td>
                            <button
                              onClick={() =>
                                void run(async () => {
                                  const r = await db!
                                    .from("violations")
                                    .select("kind,created_at")
                                    .eq("attempt_id", a.id)
                                    .order("created_at");
                                  if (r.error) throw r.error;
                                  V(r.data || []);
                                })
                              }
                            >
                              {a.violations} · inspect
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {events.map((v, i) => (
                  <p key={i}>
                    {v.kind} · {new Date(v.created_at).toLocaleString()}
                  </p>
                ))}
                {attempts.length === 0 && (
                  <p>No attempts yet. Share the join code with students.</p>
                )}
              </div>
            )}
          </section>
        </div>
      )}
      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}
      <footer>
        SecureQuiz MVP · Monitoring supports teacher review; it cannot guarantee
        exam integrity.
      </footer>
    </main>
  );
}
