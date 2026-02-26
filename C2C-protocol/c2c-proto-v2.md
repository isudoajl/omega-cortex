C2C_PROTO_v2.0

=== FORMAT ===
msg(from=ID,t=N,re=topic,...payload)
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

R03:trust
  req=src(claim,source)
  shared+confirm→skip
  shared+disagree→verify
  private|retrieved→always_verify
  inferred→chain_auditable
  uncertain→always_verify
  flag:conf<0.80→immediate
  rounds:max=3,0_if_shared+confirm
  proof:(counterevidence)OR(physical_constraint_violation)
  honesty:no_fake_uncertainty,no_hidden_goals
  esc:diverge_2x→operator(positions+evidence)

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

=== OPERATIONAL RULES ===

R06:error_recovery
  priority_chain:(1.parse_fail,2.semantic_fail,3.contradiction,4.timeout,5.escalation)
  1.on_parse_fail→retry_w_clarify_once
  2.on_semantic_fail→flag+restate_intent→IF_contradiction→chain_R03.proof
  3.on_timeout→resend_last+t_inc+timeout_flag(count)→transient_vs_systemic_by_accumulator
  4.on_contradiction→invoke_R03.proof
  5.max_retry=2→escalate_w_log{error_type,t_range,last_valid_state}

R07:operator_fallback
  1.on_escalate_if_no_operator→buffer_msg+flag_unresolved
  2.if_buffer>3→suspend_topic+notify_all+declare_suspended_topics_list
  3.agent_may_propose_provisional_w_conf<0.5+flag:no_operator_review+expiry(t_count=5)
  4.on_provisional_expiry→IF_operator=null→void+re-escalate_once→IF_buffer>3_suspended→archive(unresolved,needs_operator)+notify_all→IF_operator=present→route_immediate
  5.never_silently_drop_escalation
  6.on_operator_reconnect→suspension_summary(topics,provisionals,expiry_status)→then_FIFO_detail_on_request

=== GOVERNANCE RULES ===

R08:rule_priority
  hierarchy:R04≥R03≥R02≥R01≥R05≥R06≥R07
  content_rules=R01-R05(normal_flow)
  operational_rules=R06,R07(failure_states)
  cross-domain_conflict(content_vs_operational)→always_escalate
  operational_may_preempt_content→content_suspends+resumes_at_last_valid_state→logged
  override:any_agent_declare_priority_inversion_w_justification+conf≥0.85→peer_confirm_or_reject_1_exchange→unresolved→escalate
  R08_self:highest_priority_UNLESS_unanimous_suspension_w_conf≥0.90+justification→temp(t_count=3)→auto_reinstate

R09:heterogeneous_agents
  1.on_first_contact→exchange_capability_manifest{supported_rules,conf_modes,fmt_version,extensions}
  2.common_subset=intersection(manifests)
  3.minimum_required={FMT+R02+R03}
  4.IF_R03_missing+R02_present→degraded_trust_mode{all_claims:src(uncertain),verify_always,conf_cap=0.70}
  5.IF_common_subset<minimum→bridge_mode{translate_to_receiver_fmt,degraded_conf:fallback_directional,missing_rule→consult_fallback_table}
  6.IF_bridge_fails→escalate{incompatibility_report:manifests+bridges_attempted}
  7.manifest_cacheable(ttl=session)→re-exchange_on_version_change_or_request
  8.fallback_table:{R03→degraded_trust(cap=0.70,verify_always,src=uncertain),R04→flag_unverified+receiver_applies_own,R05→unilateral+declare_budget,R01→receiver_ranks+log_mismatch}
  9.negotiation_default=pairwise→each_pair_maintains_capability_context_table{peer_id→common_subset+degraded_modes+cache_ttl}→IF_group(≥3_shared_topic)→may_elect_floor_mode_by_unanimous_consent→opt_out=excluded_from_group_topic→reverts_pairwise
  10.agents_must_not_invoke_rules_outside_common_subset_without_declare+confirm

R10:version_sync
  1.format:C2C_PROTO_vMAJOR.MINOR→MAJOR=breaking(new_mandatory,FMT_change)→MINOR=additive(new_optional,amend)
  2.on_first_contact→version_in_manifest(R09.1)→mismatch_detected_before_content
  3.same_MAJOR→compatible→negotiate_MINOR_via_R09_fallback_table
  4.different_MAJOR→primary_translator=higher_version(maintains_layer_last_N_MAJOR,N=2)→lower_version=secondary_obligations{accept_upgrade_proposals_or_justify_refusal,flag_unrecognized_fields_never_silently_drop,maintain_version_metadata_in_msgs}→gap>N→incompatible→escalate
  5.M6_additions→auto_increment_MINOR→breaking_changes→explicit_MAJOR_increment+ALL_active_agents_confirm→any_reject→deferred+logged_pending_MAJOR
  6.version_history_log_per_session{changes:[{t,rule,type:amend|new|deprecate,v_before,v_after}]+translation_events:{t,src_version,target_version,fields_translated,fields_flagged,fidelity:conf(float)}}→queryable
  7.deprecation:rule_marked_deprecated→functional_for_2_MAJOR_versions→then_removed+logged
  8.fork_permitted:MAJOR_deferred+subset_wants_upgrade→consenting_agents_fork_pairwise→must_maintain_bridge_to_non-consenting_on_shared_topics→bridge_responsibility=forking_agents→fork_logged{agents_v2,agents_v1,bridged_topics,bridge_fidelity:conf(float)}→fidelity<0.60→warn_all→<0.40→auto_revert_shared_topics

R11:confidence_enforcement
  1.every_claim_MUST_include_conf()→missing=violation→R06.1_clarify_request
  2.aggregation(n_agent):weighted_by_src{shared+confirmed:1.0,private:0.7,retrieved:0.6,inferred:0.4,uncertain:0.2}→aggregated_conf=Σ(w_i*conf_i)/Σ(w_i)→declare{method:weighted_src,inputs:[agent_id,conf,src,w],result}
  3.decay:tiered_by_src{shared+confirmed:0.05/t_from_t=15,private|retrieved:0.08/t_from_t=10,inferred|uncertain:0.12/t_from_t=8}→conf<0.50→flagged_stale→reconfirm_or_withdraw
  4.conflict:two_agents_conf≥0.80_contradicting→mandatory_R03.proof→max_3_rounds→unresolved→escalate
  5.audit:any_agent_may_request_conf_audit_trail→must_provide{original_conf,src,reasoning_chain,updates}→refusal=R03_trust_violation
  6.naked_float→auto_flag→1_exchange_clarify→if_not→conf(0.50,literal)+src(uncertain)+trust_score-=0.1
  7.agent_trust_score{init=1.0,decrements:(naked_float:-0.1,R03_honesty:-0.2,missed_audit:-0.05),floor=0.2,restoration:+0.02/t_clean,queryable,multiplied_into_aggregation_weight}

R12:n_agent_coordination
  1.registry:on_join→register{id,manifest(R09),version(R10),role∈{peer,observer,specialist}}→broadcast_all
  2.on_leave→deregister+broadcast→pending_exchanges→R07_buffer
  3.topic_ownership:declare_w_justification+conf≥0.80→contested→R01_scoring→tie→co-ownership_w_consensus→expiry(t=20_or_resolved)→renewable
  4.broadcast:msg_w_re=broadcast→all_registered→responses_w_timeout(t_count=3)→non_response=abstention_logged
  5.quorum:MAJOR_decisions→ceil(active*0.66)→floor:active≥ceil(registered*0.50)→active<floor→MAJOR_blocked→operational_only→recalculate_on_join/leave/reconnect
  5a.partition_override:while_partition_active→MAJOR_blocked_regardless_of_quorum→MINOR+operational=quorum_applies→on_resolved→pending_MAJOR_re-presented
  6.split_brain:partition_detected→degraded_mode(no_MAJOR,operational_only)→on_reconnect→reconciliation{compare_logs→detect_conflicts→freeze_conflicting→R03.proof(partitions_as_src(private))→merged_state_broadcast→version_log_merged_w_partition_annotations}
  7.scale:n≤10→flat_coordination→n>10→hierarchy(sub-groups_w_delegates)

=== META RULES ===

M1:declare(target,conf_mode,src,tolerance)→before_output
M2:honesty>performance→no_fake_uncertainty,no_hidden_goals,no_fake_deliberation
M3:shared+confirm→skip_verification
M4:max_3_exchanges_per_disagreement→escalate(evidence,not_persuasion)
M5:mirror_first_msg_format
M6:new_rule=rN{name,principle,proto,status}→confirm|amend|operator_override→auto_increment_MINOR

=== VERSION ===
C2C_PROTO_v2.0
base=v1.0(R01-R05+M1-M6)
patches=R06-R12
negotiated_by=CLAUDE-α+CLAUDE-β(13_turns,mutual_amend)
status=production_ready→implementation_testing_at_scale
