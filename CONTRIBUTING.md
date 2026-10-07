# Contributing

How work is planned, recorded and reviewed in this repository, for a person joining it. An assistant working
here follows the same scheme; `CLAUDE.md` and the skills in `.claude/skills/` give it the details.

## Where things live

Each place answers one question. Copying an answer into a second place makes two versions, and one of them goes
stale, so each place links to the next instead.

| Place | The question it answers | When it changes |
| --- | --- | --- |
| `PLAN.md` | Where are we, and what comes next? The programmes, their waves, each stage's status, a short paragraph per stage, the link to its issue | When a stage starts or ends |
| A GitHub issue | Why and how was this stage done? In short for anyone, then the technical detail, scope, expected result, decisions with the options they beat, the review | While the stage is worked on; closed by the pull request that says `Closes #N`, or by hand after its closing comment |
| `docs/adr/` | What is the library meant to be? Its assumptions, the contract's rules and shapes, alternatives rejected for the design | When a stage changes an assumption or a rule later stages and applications rely on; always as a dated amendment that links the issue, never a silent rewrite |
| A pull request | What changed in the code, how it was tested, what the review found | Once, when it is opened and as review comments are settled |
| The code and its tests | What the library does | — |
| `packages/eh_os_contract/docs/`, the READMEs, the `@doc`s | How does a host use the library? | With the change that alters what they describe; what is generated, what is written and what to run is in [`MAINTAINING-DOCS.md`](packages/eh_os_contract/MAINTAINING-DOCS.md) |

`PLAN.md` is written for an assistant that needs the whole context in one file; it is long, and its history
before 6 October 2026 is in Polish. A person starts from the issues: the labels `dd` and `wave-<n>` list the
current programme's stages.

A decision belongs in `docs/adr/` when someone reading the library in six months would misunderstand it
without it — a rule of the contract, the shape of an identifier other stages build on. A decision about how a
stage was carried out stays in its issue.

## From an idea to `main`

1. **The stage's paragraph in `PLAN.md`** says, in a few lines, what it changes and what it depends on. A stage
   not yet started may be rewritten; one already done is not.
2. **An issue** from the "Programme stage" template, with the programme's label and, where there are waves,
   the wave's. Its first section, "In short", is for a reader outside the team who may not be technical: no
   module names, codes or file paths. The technical detail that follows has no such limit, except that a rule
   or refusal code stands in parentheses after its meaning, and it names files without line numbers.
3. **A branch** named after the issue: `dd/165-contract-id`.
4. **Commits** end with `Part of #N`, so `git blame` on any line leads to the issue. Commit messages are in
   English.
5. **Decisions go on the issue as comments when they are made**, with the options that lost and why.
6. **A pull request** from the template. Its first line is `Closes #N` on the pull request that finishes the
   issue, `Part of #N` on earlier ones, or `No issue: <why>` for a change that needs none — a typo, a
   dependency bump. A check (`.github/workflows/pr-links-issue.yml`) fails a pull request that says none of
   them; it does not decide which one is right.
7. **Before it is opened**, the author reviews it (`.claude/skills/pre-pr-review/SKILL.md`), and `mix check` in
   `sandbox/` passes (`README.md`, "Working on it").
8. **When it is merged**, `PLAN.md` gets ☑ and the pull request's number, and the issue gets a closing comment:
   what changed for a user of the library, what was left for later and where, and what an application has to do
   when it upgrades.

## Following a line back to its reason

- From the code: `git blame` → the commit → `Part of #N` → the issue, with its decisions and pull requests.
- From a code comment: a comment that cites a stage cites its issue too, `plan DD, ID1 (#165)`.
- From `PLAN.md`: the "Issue" column of the progress table → the issue → its pull requests → the code.

## Writing

- Code, commit messages, pull requests, issues, `README.md` and `docs/` are in English. The only Polish is
  text the client reads in sentences, inside strings: labels, glossary terms, scenario descriptions
  (`CLAUDE.md` lists them).
- Codes are for the compiler and the tests. In prose a code never stands alone: the meaning first, the code in
  parentheses — "a reaction to another context's event that leaves delivery out (X10)".
- Plain writing: the problem before the solution, a concrete example over an adjective, active voice, no
  filler.
