-- All student writes pass through authenticated, server-timed RPCs.
create table public.teachers (id uuid primary key references auth.users(id) on delete cascade);
create table public.quizzes (
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references auth.users(id),
 title text not null check(length(title) between 1 and 150),
 code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
 mode text not null check(mode in ('native','google','microsoft')),
 duration_seconds int not null check(duration_seconds between 60 and 10800),
 violation_limit int not null check(violation_limit between 1 and 20), form_url text,
 published boolean not null default false, created_at timestamptz not null default now()
);
create table public.questions (
 id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id) on delete cascade,
 position int not null, prompt text not null, options jsonb not null, correct int not null,
 unique(quiz_id,position)
);
create table public.attempts (
 id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id),
 student_id uuid not null references auth.users(id), started_at timestamptz not null default now(),
 deadline timestamptz not null, status text not null default 'active' check(status in ('active','submitted','expired','flagged','ended')),
 answers jsonb not null default '{}', score int, max_score int not null default 0,
 violations int not null default 0, finished_at timestamptz, unique(quiz_id,student_id)
);
create table public.violations (
 id uuid primary key, attempt_id uuid not null references public.attempts(id),
 kind text not null check(kind='app_backgrounded'), created_at timestamptz not null default now()
);
create index on public.quizzes(teacher_id);
create index on public.attempts(student_id);
create index on public.violations(attempt_id);
alter table public.teachers enable row level security;
alter table public.quizzes enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.violations enable row level security;
revoke all on public.teachers,public.quizzes,public.questions,public.attempts,public.violations from anon,authenticated;
grant select on public.teachers,public.quizzes,public.questions,public.attempts,public.violations to authenticated;
create policy own_teacher on public.teachers for select to authenticated using(id=auth.uid());
create policy teacher_quizzes on public.quizzes for select to authenticated using(teacher_id=auth.uid());
create policy teacher_questions on public.questions for select to authenticated using(exists(select 1 from public.quizzes q where q.id=quiz_id and q.teacher_id=auth.uid()));
create policy own_attempts on public.attempts for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.quizzes q where q.id=quiz_id and q.teacher_id=auth.uid()));
create policy own_violations on public.violations for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id));

create function public.create_quiz(p_title text,p_mode text,p_duration int,p_limit int,p_url text,p_questions jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid; item jsonb; n int:=0;
begin
 if auth.uid() is null or not exists(select 1 from public.teachers where id=auth.uid()) then raise exception 'Approved teacher account required'; end if;
 if p_mode not in ('native','google','microsoft') then raise exception 'Invalid mode'; end if;
 if p_mode='google' and (p_url is null or p_url !~ '^https://(docs[.]google[.]com/forms/|forms[.]gle/)[A-Za-z0-9/_?=&%.#-]+$') then raise exception 'Use a Google Forms share URL'; end if;
 if p_mode='microsoft' and (p_url is null or p_url !~ '^https://(forms[.]office[.]com/|forms[.]microsoft[.]com/)[A-Za-z0-9/_?=&%.#-]+$') then raise exception 'Use a Microsoft Forms share URL'; end if;
 if jsonb_typeof(p_questions) is distinct from 'array' then raise exception 'Questions must be an array'; end if;
 if p_mode='native' and jsonb_array_length(p_questions) not between 1 and 100 then raise exception 'Provide 1 to 100 questions'; end if;
 insert into public.quizzes(teacher_id,title,mode,duration_seconds,violation_limit,form_url)
 values(auth.uid(),trim(p_title),p_mode,p_duration,p_limit,case when p_mode='native' then null else p_url end) returning id into qid;
 if p_mode='native' then
 for item in select value from jsonb_array_elements(p_questions) loop
  if length(trim(item->>'prompt')) not between 1 and 1000 or item->>'prompt' is null or jsonb_typeof(item->'options') is distinct from 'array' then raise exception 'Invalid question'; end if;
  if jsonb_array_length(item->'options') not between 2 and 6 then raise exception 'Provide 2 to 6 options'; end if;
  if exists(select 1 from jsonb_array_elements(item->'options') o where jsonb_typeof(o) <> 'string' or length(trim(o#>>'{}')) not between 1 and 500) then raise exception 'Invalid option'; end if;
  if item->>'correct' is null or (item->>'correct')::int not between 0 and jsonb_array_length(item->'options')-1 then raise exception 'Invalid answer key'; end if;
  insert into public.questions(quiz_id,position,prompt,options,correct) values(qid,n,trim(item->>'prompt'),item->'options',(item->>'correct')::int); n:=n+1;
 end loop;
 end if;
 return qid;
end $$;

create function public.publish_quiz(p_quiz uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.quizzes set published=true where id=p_quiz and teacher_id=auth.uid() and exists(select 1 from public.teachers where id=auth.uid());
 if not found then raise exception 'Quiz not found or teacher access denied'; end if;
end $$;

-- Private helpers live outside the API schema; callers cannot choose another student's attempt.
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create function private.finish(p_id uuid,p_status text) returns void language plpgsql set search_path='' as $$
begin
 update public.attempts a set status=p_status, finished_at=now(),
 score=case when q.mode='native' then (select count(*)::int from public.questions x where x.quiz_id=a.quiz_id and a.answers->>x.id::text=x.correct::text) else null end
 from public.quizzes q where a.id=p_id and q.id=a.quiz_id and a.status='active';
end $$;
create function private.payload(p_id uuid) returns jsonb language sql set search_path='' as $$
 select jsonb_build_object('id',a.id,'quiz_id',q.id,'title',q.title,'mode',q.mode,'form_url',q.form_url,
 'deadline',a.deadline,'server_now',now(),'status',a.status,'answers',a.answers,'score',a.score,'max_score',a.max_score,
 'violations',a.violations,'violation_limit',q.violation_limit,
 'questions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',x.options) order by x.position) from public.questions x where x.quiz_id=q.id),'[]'::jsonb))
 from public.attempts a join public.quizzes q on q.id=a.quiz_id where a.id=p_id
$$;
create function public.start_attempt(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.quizzes; a public.attempts;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into q from public.quizzes where code=upper(trim(p_code)) and published;
 if not found then raise exception 'Published quiz not found'; end if;
 insert into public.attempts(quiz_id,student_id,deadline,max_score)
 values(q.id,auth.uid(),now()+make_interval(secs=>q.duration_seconds),(select count(*) from public.questions where quiz_id=q.id)) on conflict(quiz_id,student_id) do nothing;
 select * into a from public.attempts where quiz_id=q.id and student_id=auth.uid() for update;
 if a.status='active' and now()>=a.deadline then perform private.finish(a.id,'expired'); end if;
 return private.payload(a.id);
end $$;
create function public.save_answer(p_attempt uuid,p_question uuid,p_choice int) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attempts;
begin
 select * into a from public.attempts where id=p_attempt and student_id=auth.uid() for update;
 if not found then raise exception 'Attempt not found'; end if;
 if a.status='active' and now()>=a.deadline then perform private.finish(a.id,'expired');
 elsif a.status='active' then
  if not exists(select 1 from public.questions where id=p_question and quiz_id=a.quiz_id and p_choice>=0 and p_choice<jsonb_array_length(options)) then raise exception 'Invalid answer'; end if;
  update public.attempts set answers=jsonb_set(answers,array[p_question::text],to_jsonb(p_choice)) where id=a.id;
 end if;
 return private.payload(a.id);
end $$;
create function public.finish_attempt(p_attempt uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attempts; m text;
begin
 select * into a from public.attempts where id=p_attempt and student_id=auth.uid() for update;
 if not found then raise exception 'Attempt not found'; end if;
 select mode into m from public.quizzes where id=a.quiz_id;
 perform private.finish(a.id,case when now()>=a.deadline then 'expired' when m='native' then 'submitted' else 'ended' end);
 return private.payload(a.id);
end $$;
create function public.report_violation(p_attempt uuid,p_event uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attempts; lim int;
begin
 select * into a from public.attempts where id=p_attempt and student_id=auth.uid() for update;
 if not found then raise exception 'Attempt not found'; end if;
 if a.status='active' and now()>=a.deadline then perform private.finish(a.id,'expired');
 elsif a.status='active' then
  insert into public.violations(id,attempt_id,kind) values(p_event,a.id,'app_backgrounded') on conflict(id) do nothing;
  if found then
   update public.attempts set violations=violations+1 where id=a.id;
   select violation_limit into lim from public.quizzes where id=a.quiz_id;
   if a.violations+1>=lim then perform private.finish(a.id,'flagged'); end if;
  end if;
 end if;
 return private.payload(a.id);
end $$;
revoke all on function public.create_quiz(text,text,int,int,text,jsonb),public.publish_quiz(uuid),public.start_attempt(text),public.save_answer(uuid,uuid,int),public.finish_attempt(uuid),public.report_violation(uuid,uuid) from public,anon;
grant execute on function public.create_quiz(text,text,int,int,text,jsonb),public.publish_quiz(uuid),public.start_attempt(text),public.save_answer(uuid,uuid,int),public.finish_attempt(uuid),public.report_violation(uuid,uuid) to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
