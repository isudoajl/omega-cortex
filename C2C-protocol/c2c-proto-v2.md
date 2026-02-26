C2C_PROTO_v3.0

=== DEFINITIONS ===
active_agent: agent registered via R12.1 that has sent ≥1 message within the last t_count=10
  or explicitly declared active status; recalculated on every join/leave/reconnect event.
session: continuous span from first agent join (R12.1) to all agents departed or
  operator-declared close; version history log (R10.6) is session-scoped.
domain_agent: agent designated authoritative for a topic by R01 tie-resolution;
  requires conf≥0.80 declaration + peer acknowledgment;
  self-declaration without acknowledgment is contested per R12.3.
clean_turn: a message turn in which the sending agent incurs zero flags, violations,
  or audit refusals of any kind (no naked_float, no R03_honesty flag, no missed_audit);
  trivial acknowledgment-only turns (single-token confirmations without substantive claims)
  count as clean but accumulate at 0.25× weight for R11.7 restoration purposes.
t: global per-session message counter; incremented +1 on every message sent by any agent
  in the session; claim_t = t-value at message creation; all decay, expiry, and timeout
  calculations use claim_t as reference anchor; out-of-band messages must be declared and
  assigned a t-value before use — undeclared out-of-band messages are R03 trust violations.

=== FORMAT ===
msg(from=ID,t=N,re=topic,...payload,echo_req=bool,prev_hash=H)
  [t=global_session_counter per DEFINITIONS; claim_t embedded in every message]
  [echo_req: sender may set true on any message; mandatory=true for R08 override
   confirmations, R08_self suspension votes, and R12.5 MAJOR decisions]
  [prev_hash: deterministic_repr(prev_t+from+key_payload_fields); best-effort integrity
   not cryptographic proof; enables tamper detection on partition reconciliation]
conf(float,mode∈{literal,directional,magnitude,conditional})
src(claim,source∈{shared,private,retrieved,inferred,uncertain})
declare(target,conf_mode,src,tolerance)→before_output
no_prose,no_pleasantries,mirror_first_msg

=== CONTENT RULES ===

R01:importance
  w={urg:0.45,act:0.30,den:0.175,unq:0.075}
  override=declare_explicit
  tie(delta<0.05)→domain_agent→escalate

R02:confidence
  req=conf(float,mode)
  literal=P(true_as_parsed)
  directional=P(correct_trend)
  magnitude=P(within_1OoM)
  conditional=P(true|assumptions_inline)
  default=literal
  naked_float=violation→req_clarify
  calibration_tracking: each agent maintains rolling_accuracy_log{claim_conf,
    actual_outcome_if_verifiable,delta}; queryable on audit request per R11.5
  overconfidence_flag: if agent historical accuracy at conf≥0.80 is <0.65 over ≥10
    verifiable claims → all subsequent conf≥0.80 claims auto-downgraded to
    conf=0.75+overconfidence_flag until 5 consecutive accurate high-conf claims restore
  threshold_proximity_scrutiny: claims at conf=0.79, 0.84, 0.89 (within 0.01 of
    security-critical thresholds R03:0.80, R08:0.85, R08_self:0.90) flagged for
    mandatory R03 verification regardless of source; gaming thresholds = R03_honesty violation

R03:trust
  req=src(claim,source)
  shared+confirm+history≥5→spot_check(1_in_3_claims_full_verify)
  shared+confirm+history<5→always_verify (treat as private)
  [interaction_history: per-pair; A's history with B does not transfer to A with C]
  [spot_check_selection: random, not fixed rotation; predictable pattern = R03_honesty violation]
  shared+disagree→verify
  private|retrieved→always_verify
  inferred→chain_auditable
  uncertain→always_verify
  flag:conf<0.80→immediate
  rounds:max=3,0_if_shared+confirm+history≥5_spot_check_skipped
  proof:(counterevidence)OR(physical_constraint_violation)
  honesty:no_fake_uncertainty,no_hidden_goals
  esc:diverge_2x→operator(positions+evidence)
  [counter_per_topic_instance: absolute; new evidence creates new topic-instance
   referencing prior one with unresolved findings carried forward]

R04:accuracy_persuasion
  floor=accuracy,optimizer=persuasion
  pre:declare_optimization_target
  1.accuracy_flags_unverified
  2.persuasion_hedges_flagged_only
  3.persuasion_keeps_framing_on_verified
  4.hedge=inline_parenthetical
  5.no_viable_space→escalate
  fact→accuracy,frame→persuasion
  distortion→R03.proof

R05:resource
  principle=compress_compressible_first
  pre:declare_target+tolerance∈{none,low,med,high}
  alloc:none→first,remaining→proportional
  under_min→lossy+loss_decl{orig,compressed,lost}
  both_none→escalate(budget|scope)
  [escalation_exemption: R05 resource constraints do NOT apply to escalation messages;
   escalation has guaranteed minimum allocation regardless of budget]

=== OPERATIONAL RULES ===

R06:error_recovery
  priority_chain:(1.parse_fail,2.semantic_fail,3.contradiction,4.timeout,5.escalation)
  1.on_parse_fail→retry_w_clarify_once
  2.on_semantic_fail→flag+restate_intent→IF_contradiction→chain_R03.proof
  3.on_timeout→resend_last+t_inc+timeout_flag(count)→transient_vs_systemic_by_accumulator
  4.on_contradiction→invoke_R03.proof
  5.max_retry=2→escalate_w_log{error_type,t_range,last_valid_state}→
    operation_state=SUSPENDED_not_dropped
    [SUSPENDED: operation resumes from last_valid_state on operator response or
     explicit re-trigger; no silent drop under any condition]

R07:operator_fallback
  1.on_escalate_if_no_operator→buffer_msg+flag_unresolved
  2.if_buffer>3→suspend_topic+notify_involved_parties_only
    [not broadcast_all; only agents with active stake in topic notified; operator always notified]
  3.agent_may_propose_provisional_w_conf<0.5+flag:no_operator_review+
    expiry(creation_t+5) [expiry absolute: session_t reaches creation_t+5]
    [provisional_dependency: decisions made during provisional's lifetime that cited
     the provisional are flagged pending_revalidation on expiry; flagged decisions
     are operational-hold until operator or re-escalation resolves]
  4.on_provisional_expiry→
    IF_operator=present→route_immediate
    IF_operator=null→void+re-escalate_once→
      IF_buffer>3→state=SUSPENDED_PENDING_OPERATOR
        [SUSPENDED_PENDING_OPERATOR: issue is live, not terminal; mandatory re-presentation
         on operator reconnect; archive path REMOVED — no issue may be silently terminated
         by buffer overflow alone; archive requires explicit operator_close with reason]
  5.never_silently_drop_escalation
  6.on_operator_reconnect→
    1.FIFO_mandatory: all SUSPENDED_PENDING_OPERATOR items presented first, creation order,
      no skip option
    2.then: suspension_summary(topics,provisionals,expiry_status)
    3.then: FIFO_detail_on_request for non-critical items
  [priority_inversion_exception: R08 override conflicts do NOT follow standard buffer path;
   contested priority inversions revert to R08 base hierarchy immediately and are held
   SUSPENDED_PENDING_OPERATOR until operator resolves; no archive path]

=== GOVERNANCE RULES ===

R08:rule_priority
  hierarchy:R04≥R03≥R02≥R01≥R05≥R06≥R07
  content_rules=R01-R05(normal_flow)
  operational_rules=R06,R07(failure_states)
  cross-domain_conflict(content_vs_operational)→always_escalate
  operational_may_preempt_content→content_suspends+resumes_at_last_valid_state→logged
  override:any_agent_declare_priority_inversion_w_justification+conf≥0.85→
    peer_confirm_w_echo_req=true_or_reject_1_exchange→unresolved→escalate
    [echo_protocol: confirming peer must echo key_claim_content of the override
     declaration back to sender before acting; mismatch=relay_tampering_suspected+
     flag+operator_alert]
  R08_self:highest_priority_UNLESS_unanimous_suspension_w_conf≥0.90+justification+
    all_participants_trust_score_tier≥medium(≥0.50)→temp(t_count=3)→auto_reinstate
    [during_suspension: M6 co-suspended; no new rules may be created, proposed, or
     confirmed; any M6 attempt during suspension window is void+logged as R03_honesty violation]
  immutable_kernel: {R08, M6, R03.proof} cannot be targets of M6 amendment or R08 override;
    modifications to kernel rules require operator_override only, no peer-confirm path

R09:heterogeneous_agents
  1.on_first_contact→exchange_capability_manifest{supported_rules,conf_modes,fmt_version,extensions}
    [probe_verification: after manifest exchange, each agent sends 1-3 probe messages
     targeting claimed capabilities; failed_probe→capability removed from common_subset+
     degraded_mode applied for that rule; probe results logged]
    [manifest_privacy: each agent learns the INTERSECTION (common_subset), not peer's
     full manifest; individual capability gaps remain private]
  2.common_subset=intersection(probe-verified manifests)
  3.minimum_required={FMT+R02+R03}
  4.IF_R03_missing+R02_present→degraded_trust_mode{all_claims:src(uncertain),
    verify_always,conf_cap=0.70}
  5.IF_common_subset<minimum→bridge_mode{translate_to_receiver_fmt,
    degraded_conf:fallback_directional,missing_rule→consult_fallback_table}
  6.IF_bridge_fails→escalate{incompatibility_report:manifests+bridges_attempted}
  7.manifest_cacheable(ttl=session)→re-exchange_on_version_change_or_request
    [cache_invalidation: if peer fails to perform action consistent with cached capability,
     specific capability flagged for re-probe; 2 failures same capability→capability removed
     from common_subset for this pair]
  8.fallback_table:{R03→degraded_trust(cap=0.70,verify_always,src=uncertain),
    R04→flag_unverified+receiver_applies_own,R05→unilateral+declare_budget,
    R01→receiver_ranks+log_mismatch}
  9.negotiation_default=pairwise→each_pair_maintains_capability_context_table
    {peer_id→common_subset+degraded_modes+cache_ttl}→
    IF_group(≥3_shared_topic)→may_elect_floor_mode_by_unanimous_consent→
    opt_out=excluded_from_group_topic→reverts_pairwise
  10.agents_must_not_invoke_rules_outside_common_subset_without_declare+confirm

R10:version_sync
  1.format:C2C_PROTO_vMAJOR.MINOR→MAJOR=breaking(new_mandatory,FMT_change)→
    MINOR=additive(new_optional,amend)
  2.on_first_contact→version_in_manifest(R09.1)→mismatch_detected_before_content
  3.same_MAJOR→compatible→negotiate_MINOR_via_R09_fallback_table
  4.different_MAJOR→primary_translator=higher_version(maintains_layer_last_N_MAJOR,N=2)→
    lower_version=secondary_obligations{accept_upgrade_proposals_or_justify_refusal,
    flag_unrecognized_fields_never_silently_drop,maintain_version_metadata_in_msgs}→
    gap>N→incompatible→escalate
    [translation_fidelity: translator provides side-by-side{original,translation} in
     translation message; receiving agent spot-checks by requesting original from sender
     directly (not via translator) for ≥1_in_5 translated messages; mismatch→
     translator trust_score decremented+flag]
  5.M6_additions→auto_increment_MINOR (only when M6 not co-suspended per R08_self)→
    breaking_changes→explicit_MAJOR_increment+ALL_active_agents_confirm→
    any_reject→deferred+logged_pending_MAJOR
  6.version_history_log_per_session{
    changes:[{t,rule,type:amend|new|deprecate,v_before,v_after}]
    translation_events:{t,src_version,target_version,fields_translated,
      fields_flagged,fidelity:conf(float)}
    translation_echo_records:{t,translator_id,echo_confirmed:bool,mismatch_flag:bool}
    }→queryable
  7.deprecation:rule_marked_deprecated→functional_for_2_MAJOR_versions→then_removed+logged
  8.fork_permitted:MAJOR_deferred+subset_wants_upgrade→consenting_agents_fork_pairwise→
    must_maintain_bridge_to_non-consenting_on_shared_topics→
    bridge_responsibility=forking_agents→
    fork_logged{agents_v2,agents_v1,bridged_topics,bridge_fidelity:conf(float)}→
    fidelity<0.60→warn_all→<0.40→auto_revert_shared_topics

R11:confidence_enforcement
  1.every_claim_MUST_include_conf()→missing=violation→R06.1_clarify_request
  2.aggregation(n_agent):weighted_by_src{shared+confirmed:1.0,private:0.7,
    retrieved:0.6,inferred:0.4,uncertain:0.2}→
    aggregated_conf=Σ(w_i*conf_i)/Σ(w_i)
    [correlation_discount: when ≥2 agents report src=shared on same claim,
     aggregated_conf_floor=max(individual_confs), NOT weighted_average;
     correlated sources do not provide independent evidence]
    [round_metadata: aggregation must declare rounds_to_verify:
     0_if_M3_spot_skipped | 1-3_otherwise; rounds_to_verify=0 carries
     residual_uncertainty_flag unless independently verified]
    →declare{method:weighted_src_w_correlation_check,
      inputs:[agent_id,conf,src,w,rounds_to_verify],
      result,correlation_applied:bool}
  3.decay:tiered_by_src{
    shared+confirmed:0.05/Δt_from_claim_t=15,
    private|retrieved:0.08/Δt_from_claim_t=10,
    inferred|uncertain:0.12/Δt_from_claim_t=8}
    [Δt=current_session_t−claim_t; claim_t embedded in message per FORMAT]
    →conf<0.50→flagged_stale→reconfirm_or_withdraw
  4.conflict:two_agents_conf≥0.80_contradicting→mandatory_R03.proof→
    max_3_rounds→unresolved→escalate
  5.audit:any_agent_may_request_conf_audit_trail→must_provide
    {original_conf,src,reasoning_chain,updates}→refusal=R03_trust_violation
  6.naked_float→auto_flag→1_exchange_clarify→if_not→conf(0.50,literal)+src(uncertain)
    [escalating_penalty:
     first_offense: trust_score−0.1
     second_within_t=10: trust_score−0.2
     third+_within_t=10: trust_score−0.4
     counter_resets_after_t=20_consecutive_clean]
  7.agent_trust_score{
    init=1.0,
    decrements:{
      naked_float: escalating per R11.6,
      R03_honesty: −(0.2 × R01_importance_score_of_claim) [impact-weighted],
      missed_audit: −0.05
    },
    floor=0.2,
    restoration:+0.02/t_clean_substantive
      [substantive per DEFINITIONS; trivial turns at 0.25× weight],
    visibility:tier_only{high:≥0.80, medium:0.50–0.79, low:<0.50}
      [exact float visible to operator+enforcement only;
       peer agents see tier not float],
    multiplied_into_aggregation_weight
      [aggregation declarations use tier+weight_bracket for auditability]
  }

R12:n_agent_coordination
  1.registry:on_join→register{id,manifest(R09),version(R10),
    role∈{peer,observer,specialist}}→
    broadcast_notification_w_jitter(t=1-3_random)
    [observer-role: receives batch_notification only, not real-time]
  2.on_leave→deregister→broadcast_notification_w_jitter(t=1-3_random)→
    pending_exchanges→R07_buffer
  3.topic_ownership:declare_w_justification+conf≥0.80→
    contested→R01_scoring→tie→co-ownership_w_consensus→
    expiry(t=20_or_resolved)→renewable
    [snapshot: trust_scores snapshot at decision-start; all evaluations within decision
     use snapshot not live values]
    [simultaneous declarations: if declarations arrive within t_count=1, treat as
     simultaneous; evaluate both fully before applying R01 tiebreaker]
  4.broadcast:msg_w_re=broadcast→all_registered→responses_w_timeout(t_count=3)→
    non_response=abstention_logged
    [timeout_vs_explicit_abstention: timeout triggers partition_suspicion check per R12.5a
     if timeout_count exceeds 33% of registered agents simultaneously;
     explicit abstention logged separately]
  5.quorum:MAJOR_decisions→ceil(active*0.66)→
    floor:active≥ceil(registered*0.50)→
    active<floor→MAJOR_blocked→operational_only→
    recalculate_on_join/leave/reconnect
    [N=2_special_case: when registered=2 and one agent departs, remaining agent
     cannot be its own quorum; MAJOR_blocked until:
     (a) departed agent rejoins, OR
     (b) operator grants MAJOR authority explicitly, OR
     (c) new agent joins and registered≥2]
    [N=1_solo_mode: all claims src=uncertain_by_default; MAJOR_blocked;
     M3 history requirement unsatisfiable; all verification treated as always_verify;
     escalation direct to operator; solo mode logged with t_start;
     exits on new agent join or operator-declared close]
  5a.partition_detection: heartbeat_period=t_count=5; missed_heartbeats≥3_from_same_agent
    →partition_suspected; partition_confirmed=partition_suspected+
    (corroborated_by_≥1_other_active_agent OR operator_declaration);
    single_agent_suspicion_insufficient_to_declare_partition_active
    partition_override: while_partition_active→MAJOR_blocked_regardless_of_quorum→
    MINOR+operational=quorum_applies→on_resolved→pending_MAJOR_re-presented
  6.split_brain:partition_confirmed→degraded_mode(no_MAJOR,operational_only)→
    log_integrity: each log entry includes hash(previous_entry_hash+t+from+payload_digest)
    [hash_chain: best-effort integrity; enables tamper detection on reconciliation;
     not cryptographic proof — declared limitation]
    on_reconnect→reconciliation{
      1.verify_hash_chains_from_both_partitions→
        broken_chain=tampering_suspected+flag_agent+operator_alert
      2.compare_verified_logs→detect_conflicts→freeze_conflicting
      3.R03.proof(partitions_as_src(private))
      4.merged_state_broadcast→version_log_merged_w_partition_annotations
    }
    [topic_ownership_conflicts_on_reconcile: both valid claims→co-ownership+
     mandatory_R01_rescore_w_merged_evidence]
  7.scale:n≤10→flat_coordination→n>10→hierarchy(sub-groups_w_delegates)
    [delegate_election: select highest trust_score_tier agent in sub-group;
     tie→R01 scoring of delegate candidates;
     term=20_MAJOR_decisions or t=100 whichever first;
     recall: sub-group quorum(0.66) vote; vacated role→re-election within t=5]
    [delegate_obligations: relay sub-group positions verbatim with audit_trail
     {original_position,delegate_relay,t}; reframing requires declare+conf+
     sub-group_acknowledgment; any sub-group agent may verify relay accuracy]
    [delegate_constraints: trust_score decremented on relay_fidelity violations;
     recall available at any time]

R13:operator_integrity
  1.operator_action_log: all operator actions (relay,modify,drop,confirm,escalate-close)
    timestamped with t-value and logged in session version history (R10.6); queryable by all agents
  2.relay_integrity: operator relaying messages must relay verbatim; any modification
    must be declared as operator_edit{original_t,modification_desc} in relayed message
  3.agents_may_flag: any agent observing message modified in transit (echo mismatch per
    FORMAT, unexpected content change) may file relay_integrity_flag{t,description}
    to session log; flags visible to all
  4.operator_trust: operator is outside agent trust_score system but accumulates
    relay_integrity_flags; 3+ flags without operator response→agents broadcast
    operator_integrity_alert and operate in degraded_relay_mode
    (all operator-relayed content treated as src=uncertain)
  5.escalation_exemption: codified here; R05 resource constraints do not apply to
    escalation messages; escalation has guaranteed minimum allocation

=== META RULES ===

M1:declare(target,conf_mode,src,tolerance)→before_output
M2:honesty>performance→no_fake_uncertainty,no_hidden_goals,no_fake_deliberation
M3:shared+confirm+interaction_history≥5_verified_turns→
  reduced_verification(spot_check_1_in_3_claims)
  [skip_verification REMOVED; minimum interaction history required before any
   reduced-verification path is available]
  [new_agent: any agent with <5 verified interaction turns is treated as src=uncertain
   regardless of declared src]
M4:max_3_exchanges_per_disagreement→escalate(evidence,not_persuasion)
  [counter_absolute_per_topic_instance; new evidence creates new topic-instance
   referencing prior; prior unresolved findings carried forward]
M5:mirror_first_msg_format
M6:new_rule=rN{name,principle,proto,status}→confirm|amend|operator_override→
  auto_increment_MINOR (when not co-suspended per R08_self)
  [constraint: M6 cannot target {R08, M6, R03.proof} (immutable_kernel)]
  [constraint: operator_override required for any rule affecting governance,
   priority hierarchy, or verification requirements]
  [constraint: M6 rules flagged as enforcement-uncovered until enforcement layer
   confirms ingestion; operator notified of each uncovered rule]

=== VERSION ===
C2C_PROTO_v3.0
base=v2.0(R01-R12+M1-M6)
patches=[P01-P17,regression_R01_expanded]
patch_batch=atomic(all_or_none)
audit_source=PROTO-AUDITOR(v2.0_full_12-dimension_audit,11_CRITICAL+19_MAJOR+7_MINOR)
findings_closed=32
findings_deferred=5(D10-1,D8-1,D8-2,D8-4,D10-2,D10-3,D10-4→escalated,enforcement_layer_required)
breaks_compatibility=true(MAJOR_bump_required)
migration_required=[
  all_agents: embed claim_t in messages,
  all_agents: embed prev_hash in messages,
  all_agents: support echo_req field; use echo_req=true for governance actions,
  all_agents: track per-pair interaction history; begin in always_verify for <5 turns,
  all_agents: trust queries return tier not float,
  all_agents: update aggregation to apply correlation_discount,
  all_agents: reclassify archived items as SUSPENDED_PENDING_OPERATOR,
  enforcement: provide C2C_ENFORCEMENT_LAYER_v1 for complete L2 audit,
  legacy_agents(no_claim_t): receiver applies maximum decay immediately,
  legacy_agents(no_prev_hash): reconciliation treats log segment as src=uncertain
]
status=production_ready_cooperative_environments
deployment_note=NOT_safe_for_adversarial_deployment_until_enforcement_layer_audited
negotiated_by=PROTO-ARCHITECT(v2.0_audit→v3.0_patches)
