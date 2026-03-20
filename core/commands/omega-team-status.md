---
name: omega:team-status
description: "Dashboard showing shared team knowledge statistics, recent contributions, active incidents, hotspot map, and unresolved conflicts from the Cortex shared store (.omega/shared/). Read-only — does not modify any data."
---

# Workflow: Team Status

Display a dashboard of the team's shared knowledge from the Cortex shared store at `.omega/shared/`. This is a read-only command that does NOT modify any data (no INSERT, UPDATE, or DELETE to shared files). It reads `.omega/shared/` files directly and works without memory.db.

## Prerequisite Check

Before displaying the dashboard, check if the Cortex shared store exists:

```bash
if [ ! -d ".omega/shared" ]; then
    echo "Cortex not initialized. Run setup.sh to enable."
    exit 0
fi
```

If `.omega/shared/` does not exist, output the message above and stop. Do not error — this is a graceful exit.

## Pipeline Tracking

Register a `workflow_runs` entry at the start (requires memory.db — skip if unavailable):

```sql
INSERT INTO workflow_runs (type, description, scope, status)
VALUES ('team-status', 'Display team shared knowledge dashboard', 'cortex', 'running');
```

At completion, UPDATE the workflow_runs entry:

```sql
UPDATE workflow_runs
SET status = 'completed', completed_at = datetime('now')
WHERE id = $RUN_ID;
```

## Dashboard Sections

The dashboard consists of 5 sections. Use python3 for all JSONL and JSON parsing. Display each section sequentially.

### Section 1: Shared Knowledge Stats

Count entries by category across all shared JSONL/JSON files:

```bash
python3 -c "
import json, glob, os

categories = {
    'behavioral learnings': 'behavioral-learnings.jsonl',
    'incidents': 'incidents/*.json',
    'hotspots': 'hotspots.jsonl',
    'lessons': 'lessons.jsonl',
    'patterns': 'patterns.jsonl',
    'decisions': 'decisions.jsonl'
}

print('=== Shared Knowledge Stats ===')
for cat, pattern in categories.items():
    path = os.path.join('.omega/shared', pattern)
    files = glob.glob(path)
    count = 0
    for f in files:
        if f.endswith('.jsonl'):
            with open(f) as fh:
                count += sum(1 for line in fh if line.strip())
        elif f.endswith('.json'):
            count += 1
    print(f'  {cat}: {count}')
"
```

Display as a summary table:

```
=== Shared Knowledge Stats ===
  behavioral learnings: N
  incidents: N
  hotspots: N
  lessons: N
  patterns: N
  decisions: N
```

### Section 2: Recent Contributions

Show the last 10 shared entries across all categories, sorted by date, with contributor, category, and date:

```bash
python3 -c "
import json, glob, os

entries = []
jsonl_cats = {
    'behavioral-learnings.jsonl': 'behavioral_learning',
    'hotspots.jsonl': 'hotspot',
    'lessons.jsonl': 'lesson',
    'patterns.jsonl': 'pattern',
    'decisions.jsonl': 'decision'
}

for filename, category in jsonl_cats.items():
    path = os.path.join('.omega/shared', filename)
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entry = json.loads(line)
                        entries.append({
                            'contributor': entry.get('contributor', 'unknown'),
                            'category': category,
                            'date': entry.get('shared_at', entry.get('timestamp', 'unknown'))
                        })
                    except json.JSONDecodeError:
                        pass

# Also check incidents
for inc_file in glob.glob('.omega/shared/incidents/*.json'):
    try:
        with open(inc_file) as f:
            entry = json.load(f)
            entries.append({
                'contributor': entry.get('contributor', 'unknown'),
                'category': 'incident',
                'date': entry.get('shared_at', entry.get('resolved_at', 'unknown'))
            })
    except (json.JSONDecodeError, FileNotFoundError):
        pass

# Sort by date descending, take last 10
entries.sort(key=lambda e: e['date'], reverse=True)
recent = entries[:10]

print()
print('=== Recent Contributions ===')
print(f\"{'Contributor':<30} {'Category':<25} {'Date':<20}\")
print('-' * 75)
for e in recent:
    print(f\"{e['contributor']:<30} {e['category']:<25} {e['date']:<20}\")
if not recent:
    print('  (no shared entries yet)')
"
```

### Section 3: Active Shared Incidents

List all resolved incidents available to the team from `.omega/shared/incidents/*.json`:

```bash
python3 -c "
import json, glob

print()
print('=== Active Shared Incidents ===')
incidents = []
for f in sorted(glob.glob('.omega/shared/incidents/*.json')):
    try:
        with open(f) as fh:
            inc = json.load(fh)
            incidents.append(inc)
    except (json.JSONDecodeError, FileNotFoundError):
        pass

if incidents:
    for inc in incidents:
        inc_id = inc.get('incident_id', 'unknown')
        title = inc.get('title', inc.get('description', 'no title'))
        status = inc.get('status', 'resolved')
        contributor = inc.get('contributor', 'unknown')
        print(f'  {inc_id}: {title} [{status}] (by {contributor})')
else:
    print('  (no shared incidents)')
"
```

Only resolved incidents should be shared to the team store. This section surfaces them for reference.

### Section 4: Team Hotspot Map

Show the top 10 shared hotspots with contributor counts from `.omega/shared/hotspots.jsonl`:

```bash
python3 -c "
import json, os
from collections import defaultdict

print()
print('=== Team Hotspot Map ===')

path = '.omega/shared/hotspots.jsonl'
if not os.path.exists(path):
    print('  (no shared hotspots)')
else:
    hotspots = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    hotspots.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    # Aggregate by file path, count unique contributors
    by_file = defaultdict(lambda: {'count': 0, 'contributors': set(), 'severity': 0})
    for h in hotspots:
        fp = h.get('file_path', h.get('path', 'unknown'))
        by_file[fp]['count'] += 1
        by_file[fp]['contributors'].add(h.get('contributor', 'unknown'))
        by_file[fp]['severity'] = max(by_file[fp]['severity'], h.get('severity', 0))

    # Sort by count descending, take top 10
    sorted_hotspots = sorted(by_file.items(), key=lambda x: x[1]['count'], reverse=True)[:10]

    if sorted_hotspots:
        print(f\"{'File':<50} {'Hits':<6} {'Contributors':<6} {'Severity':<8}\")
        print('-' * 70)
        for fp, data in sorted_hotspots:
            print(f\"{fp:<50} {data['count']:<6} {len(data['contributors']):<6} {data['severity']:<8}\")
    else:
        print('  (no shared hotspots)')
"
```

### Section 5: Unresolved Conflicts

Display any unresolved conflicts from `.omega/shared/conflicts.jsonl`:

```bash
python3 -c "
import json, os

print()
print('=== Unresolved Conflicts ===')

path = '.omega/shared/conflicts.jsonl'
if not os.path.exists(path):
    print('  (no conflicts file)')
else:
    conflicts = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    conflicts.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    unresolved = [c for c in conflicts if c.get('status', 'unresolved') != 'resolved']

    if unresolved:
        for c in unresolved:
            cid = c.get('conflict_id', 'unknown')
            category = c.get('category', 'unknown')
            desc = c.get('description', c.get('content', 'no description'))
            contributors = c.get('contributors', [])
            print(f'  {cid}: [{category}] {desc}')
            if contributors:
                print(f'    Contributors: {', '.join(contributors)}')
    else:
        print('  (no unresolved conflicts)')
"
```

## Error Handling

- If `.omega/shared/` does not exist: output "Cortex not initialized. Run setup.sh to enable." and exit gracefully
- If individual JSONL/JSON files are missing or malformed: skip them and continue with remaining sections
- If python3 is not available: report the error and suggest installing Python 3
- If memory.db is unavailable: skip pipeline tracking (workflow_runs) but still display the dashboard
- Never crash on bad data — display what you can, skip what you cannot

## Institutional Memory Protocol

- **Briefing**: This is a read-only dashboard. No memory.db briefing is needed beyond pipeline tracking.
- **Incremental logging**: Not applicable — this command only reads and displays data.
- **Close-out**: Update the workflow_runs entry to 'completed' when done.
