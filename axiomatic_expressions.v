(* Copyright (c) 2012-2015, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export axiomatic.
Require Import axiomatic_graph type_system_decidable.
Require Import expression_eval_smallstep.
Require Import assignments_separation expression_eval_separation.
Local Open Scope ctype_scope.

Section axiomatic_expressions.
Context `{EnvSpec K}.
Implicit Types Γ : env K.
Implicit Types o : index.
Implicit Types Δ : memenv K.
Implicit Types δ : funenv K.
Implicit Types m : mem K.
Implicit Types e : expr K.
Implicit Types τ σ : type K.
Implicit Types a : addr K.
Implicit Types v : val K.
Implicit Types ν : lrval K.
Implicit Types k : ctx K.
Implicit Types φ : focus K.
Implicit Types S : state K.

Arguments assert_holds _ _ _ _ _ _ _ _ : simpl never.

Hint Extern 1 (_ ⊥ _) => solve_mem_disjoint.
Hint Extern 1 (⊥ _) => solve_mem_disjoint.
Hint Extern 1 (sep_valid _) => solve_mem_disjoint.
Hint Extern 1 (_ ≤ _) => omega.

Hint Resolve Forall_app_2.
Hint Immediate memenv_subseteq_forward.
Hint Immediate cmap_valid_memenv_valid.
Hint Resolve cmap_empty_valid cmap_erased_empty mem_locks_empty.
Hint Resolve cmap_union_valid_2 cmap_erased_union cmap_erase_valid.

Hint Immediate ax_disjoint_expr_compose_diagram.
Hint Immediate ax_expr_disjoint_compose_diagram.
Hint Immediate ax_expr_invariant_emp.
Hint Immediate ax_disjoint_compose_diagram.

Hint Immediate val_new_typed perm_full_mapped.
Hint Resolve mem_alloc_valid mem_free_valid.
Hint Immediate lockset_empty_valid.
Hint Extern 0 (_ ⊢ _ : _) => typed_constructor.
Hint Extern 0 (unframe ax_disjoint_cond _ _ _ _ _ _ _) => by constructor.
Hint Extern 0 (focus_locks_valid _ _) => by constructor.

(** ** Basic rules *)
Lemma ax_expr_weaken Γ δ P P' A Q Q' e :
  P ⊆{Γ} P' → (∀ ν, Q' ν ⊆{Γ} Q ν) →
  Γ\ δ\ A ⊨ₑ {{ P' }} e {{ Q' }} → Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q }}.
Proof.
  intros HP HQ Hax Γ' Δ n ρ m τlr ??????????.
  apply ax_weaken with (ax_expr_cond ρ A) (ax_expr_post Q' τlr) n; auto.
  destruct 2; constructor; auto. apply HQ; eauto using indexes_valid_weaken.
Qed.
Lemma ax_expr_weaken_pre Γ δ A P P' Q e :
  P ⊆{Γ} P' →
  Γ\ δ\ A ⊨ₑ {{ P' }} e {{ Q }} → Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q }}.
Proof. eauto using ax_expr_weaken. Qed.
Lemma ax_expr_weaken_post Γ δ A P Q Q' e :
  (∀ ν, Q' ν ⊆{Γ} Q ν) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q' }} → Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q }}.
Proof. eauto using ax_expr_weaken. Qed.
Lemma ax_expr_frame_r Γ δ B A P Q e :
  Γ\ δ\ B ⊨ₑ {{ P }} e {{ λ ν, Q ν }} →
  Γ\ δ\ B ⊨ₑ {{ P ★ A }} e {{ λ ν, Q ν ★ A }}.
Proof.
  intros Hax Γ' Δ n ρ m τlr ???? Hlocks ???? (m1&m2&?&?&?&?).
  destruct (cmap_erase_union_inv m m1 m2)
    as (m1'&m2'&->&?&->&->); simplify_mem_disjoint_hyps; auto.
  rewrite mem_locks_union in Hlocks by auto; decompose_empty.
  apply ax_frame with (ax_expr_cond ρ B) (ax_expr_post Q τlr);
    eauto using ax_expr_cond_frame_diagram_simple.
  { apply Hax; eauto using ax_expr_invariant_weaken, @sep_union_subseteq_l. }
  intros Δ' n' φ' m' ?????; destruct 1 as [ν Ω ????]; constructor; eauto.
  { rewrite mem_locks_union by auto. esolve_elem_of. }
  exists (cmap_erase m) (cmap_erase m2'); split_ands;
    eauto using cmap_erase_union, assert_weaken.
  by rewrite <-!cmap_erase_disjoint_le.
Qed.
Lemma ax_expr_frame_l Γ δ B A P Q e :
  Γ\ δ\ B ⊨ₑ {{ P }} e {{ λ ν, Q ν }} →
  Γ\ δ\ B ⊨ₑ {{ A ★ P }} e {{ λ ν, A ★ Q ν }}.
Proof.
  setoid_rewrite (commutative (R:=(≡{Γ})) (★)%A A). apply ax_expr_frame_r.
Qed.
Lemma ax_expr_exist_pre {A} Γ δ (B : assert K) (P : A → assert K) Q e :
  (∀ x, Γ\ δ\ B ⊨ₑ {{ P x }} e {{ Q }}) →
  Γ\ δ\ B ⊨ₑ {{ ∃ x, P x }} e {{ Q }}.
Proof. intros Hax Γ' Δ n k m τlr HΓ Hd ??????? [x Hpre]; by apply (Hax x). Qed.
Lemma ax_expr_invariant_r Γ δ B A P Q e :
  Γ\ δ\ A ★ B ⊨ₑ {{ P }} e {{ λ ν, Q ν }} →
  Γ\ δ\ B ⊨ₑ {{ P ★ A }} e {{ λ ν, Q ν ★ A }}.
Proof.
  revert Γ. cut (∀ Γ n Δ ρ k φ m τlr,
    ✓ Γ → ✓{Δ}* ρ →
    ax_graph (ax_expr_cond ρ (A ★ B)) (ax_expr_post Q τlr) Γ δ Δ ρ n k φ m →
    (k = [] → ∀ mA,
      ⊥ [m; mA] → ✓{Γ,Δ} mA → cmap_erased mA → mem_locks mA = ∅ →
      assert_holds A Γ Δ ρ n mA →
      ax_graph (ax_expr_cond ρ B)
         (ax_expr_post (λ ν, Q ν ★ A) τlr)%A Γ δ Δ ρ n k φ (m ∪ mA)) ∧
    (k ≠ [] →
      ax_graph (ax_expr_cond ρ B)
               (ax_expr_post (λ ν, Q ν ★ A)%A τlr) Γ δ Δ ρ n k φ m)).
  { intros help Γ Hax Γ' Δ n ρ m' τlr ???? Hm ??? (mB&?&?&?&?&?)
      (m&mA&?&?&?&?); simplify_equality.
    destruct (cmap_erase_union_inv_r m' m mA)
      as (m''&->&?&->&?); simplify_mem_disjoint_hyps; auto.
    rewrite mem_locks_union in Hm by auto; decompose_empty.
    refine (proj1 (help Γ' n Δ ρ [] (Expr e) m'' τlr _ _ _ ) _ mA _ _ _ _ _); auto.
    apply Hax; auto. exists (mA ∪ mB); split_ands; eauto.
    * rewrite mem_locks_union by auto. by apply empty_union_L.
    * exists mA mB; split_ands; auto. }
  clear P. intros Γ n.
  induction n as [[|n] IH] using lt_wf_ind; [repeat constructor|].
  intros Δ ρ k φ m τlr ??;
    inversion 1 as [|??? [ν ?????]|???? Hred Hstep]; subst.
  { split; [|done]; intros _ mA ? HmA ??; do 2 constructor; auto.
    { rewrite mem_locks_union by auto; esolve_elem_of. }
    rewrite cmap_erase_union.
    exists (cmap_erase m) (cmap_erase mA); split_ands; auto.
    + by rewrite <-!cmap_erase_disjoint_le.
    + by rewrite cmap_erased_spec by done. }
  split.
  * intros -> mA ?????; apply ax_further.
    { intros Δ' n' ????? Hframe; inversion_clear Hframe as [mB mf|];
        simplify_equality; simplify_mem_disjoint_hyps.
      rewrite <-!(sep_associative m), (sep_commutative mA),
        <-(sep_associative mf), (sep_associative m) by auto.
      eapply Hred, ax_frame_in_expr; eauto.
      + rewrite mem_locks_union by auto. by apply empty_union_L.
      + exists mA mB; split_ands; eauto using assert_weaken. }
    intros Δ' n' ?? S' ??? Hframe p ?; inversion_clear Hframe as [mB mf|];
      simplify_equality; simplify_mem_disjoint_hyps.
    feed inversion (Hstep Δ' n' (m ∪ mA ∪ mf ∪ mB) (InExpr mf (mA ∪ mB)) S')
      as [Δ'' k' n'' φ' m' ?? Hunframe]; subst; auto.
    { constructor; auto.
      + by rewrite <-!(sep_associative m), (sep_commutative mA),
          <-(sep_associative mf), (sep_associative m) by auto.
      + rewrite mem_locks_union by auto. by apply empty_union_L.
      + exists mA mB; split_ands; eauto using assert_weaken. }
    inversion Hunframe as [| |m''|]; subst; simplify_mem_disjoint_hyps.
    + apply mk_ax_next with Δ'' (m' ∪ mA); auto using focus_locks_valid_union.
      - apply ax_unframe_expr_to_expr; auto.
        by rewrite <-!(sep_associative m'),
          (sep_commutative mA mf), !sep_associative by auto.
      - destruct (λ H, IH n' H Δ'' ρ [] φ' m' τlr);
          eauto using assert_weaken, indexes_valid_weaken.
    + apply mk_ax_next with Δ'' (m'' ∪ mA ∪ mB); auto.
      - apply ax_unframe_expr_to_fun with (m'' ∪ mA); auto.
        by rewrite <-!(sep_associative m''),
          (sep_commutative mA mf), !sep_associative by auto.
      - by rewrite <-sep_associative by auto.
      - destruct (λ H, IH n' H Δ'' ρ k' φ' (m'' ∪ mA ∪ mB) τlr);
          eauto using assert_weaken, indexes_valid_weaken.
        by rewrite <-sep_associative by auto.
  * intros ?; apply ax_further_alt.
    intros Δ' n' ????? Hframe;
      inversion_clear Hframe as [|mf]; simplify_equality.
    split; [eapply Hred, ax_frame_in_fun; eauto|].
    intros S' p ?.
    feed inversion (Hstep Δ' n' (m ∪ mf) (InFun mf) S')
      as [Δ'' k' n'' φ' m' ?? Hunframe]; subst; auto.
    { by apply ax_frame_in_fun. }
    inversion Hunframe as [|?????? HmAmB (mA&mB&?&?&?&?)| |];
      subst; simplify_mem_disjoint_hyps.
    + rewrite mem_locks_union in HmAmB by auto; decompose_empty.
      apply mk_ax_next with Δ'' (m' ∪ mA); auto using focus_locks_valid_union.
      - eapply ax_unframe_fun_to_expr with mB;
          eauto 3 using cmap_erased_subseteq, @sep_union_subseteq_r'.
        by rewrite <-!(sep_associative m'),
          (sep_commutative mA mf), !sep_associative by auto.
      - destruct (λ H, IH n' H Δ'' ρ [] φ' m' τlr); eauto 10 using
          indexes_valid_weaken, cmap_erased_subseteq, @sep_union_subseteq_l',
          assert_weaken.
    + apply mk_ax_next with Δ'' m'; auto; [by apply ax_unframe_fun_to_fun|].
      destruct (λ H, IH n' H Δ'' ρ k' φ' m' τlr);
        eauto using indexes_valid_weaken.
Qed.
Lemma ax_expr_invariant_l Γ δ B A P Q e :
  Γ\ δ\ A ★ B ⊨ₑ {{ P }} e {{ λ ν, Q ν }} →
  Γ\ δ\ B ⊨ₑ {{ A ★ P }} e {{ λ ν, A ★ Q ν }}.
Proof.
  intros. setoid_rewrite (commutative (R:=(≡{Γ})) (★)%A A).
  by apply ax_expr_invariant_r.
Qed.

(** ** Structural rules *)
Lemma ax_expr_base Γ δ A P Q e ν :
  P ⊆{Γ} (Q ν ∧ e ⇓ ν)%A →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q }}.
Proof.
  intros HPQ Γ' Δ n ρ m τlr ?????? He Hm HA HP.
  destruct (HPQ Γ' Δ ρ n (cmap_erase m)) as [HQ (τlr'&?&?)]; auto.
  assert (τlr' = τlr) by (by simplify_type_equality'); subst.
  cut (∀ Δ' e',
    Δ ⇒ₘ Δ' → locks e' = ∅ → ⟦ e' ⟧ Γ' ρ m = Some ν → (Γ',Δ',ρ.*2) ⊢ e' : τlr →
    ax_graph (ax_expr_cond ρ A)
      (ax_expr_post Q τlr) Γ' δ Δ' ρ n [] (Expr e') m).
  { intros help. apply (help Δ); rewrite <-1?expr_eval_erase; auto. }
  assert (✓{Γ',Δ} (cmap_erase m)) by eauto.
  clear HPQ HP He. induction n as [[|n] IH] using lt_wf_ind; [by constructor |].
  intros Δ' e' ? He' Heval ?. destruct (decide (is_nf e')) as [Hnf|Hnf].
  { inversion Hnf; simplify_option_equality; typed_inversion_all.
    apply ax_done; split; eauto using lrval_typed_weaken, assert_weaken. }
  apply ax_further_alt.
  intros Δ'' n''; inversion_clear 4 as [mA mf|]; simplify_equality'; split.
  { destruct (is_nf_is_redex e') as (E&e''&?&->); auto.
    destruct (expr_eval_subst_ehstep Γ' ρ (m ∪ mf ∪ mA) E e'' ν)
      as (e2&?&?); auto; try solve_rcred.
    eapply expr_eval_subseteq with Δ'' m τlr;
      eauto using indexes_valid_weaken, @sep_union_subseteq_l_transitive,
      @sep_union_subseteq_l', expr_typed_weaken. }
  intros S' p; pattern S'.
  apply (rcstep_focus_inv _ _ _ _ _ _ p); clear p; try done.
  * intros E e1 e2 m2 -> p ?.
    rewrite expr_eval_subst in Heval; destruct Heval as (ν'&?&?).
    destruct (ectx_subst_typed_rev Γ' Δ'' (ρ.*2) E e1 τlr)
      as (τlr''&?&?); eauto using expr_typed_weaken.
    rewrite ectx_subst_locks in He'; decompose_empty.
    assert (⟦ e1 ⟧ Γ' ρ (m ∪ mf ∪ mA) = Some ν').
    { eapply expr_eval_subseteq with Δ'' m τlr'';
        eauto using indexes_valid_weaken, @sep_union_subseteq_l_transitive,
        @sep_union_subseteq_l', expr_typed_weaken. }
    assert (locks (subst E e2) = ∅).
    { erewrite ectx_subst_locks, ehstep_expr_eval_locks by eauto.
      esolve_elem_of. }
    assert (m ∪ mf ∪ mA = m2) by eauto using ehstep_expr_eval_mem; subst.
    apply mk_ax_next with Δ'' m; auto.
    { apply ax_unframe_expr_to_expr; auto. }
    { esolve_elem_of. }
    apply IH; eauto 7 using
      ectx_subst_typed, ehstep_expr_eval_typed, indexes_valid_weaken,
      assert_weaken, ax_expr_invariant_weaken, @sep_reflexive.
    by erewrite (subst_preserves_expr_eval _ _ _ _ _ (%# ν')%E)
      by (simplify_option_equality; eauto using ehstep_expr_eval).
  * intros E Ω f τs Ωs vs ? -> ?.
    rewrite expr_eval_subst in Heval;
      destruct Heval as (?&?&?); simplify_option_equality.
  * intros E e1 -> ? []; simpl; rewrite <-sep_associative by auto.
    apply expr_eval_subst_ehsafe with E ν; auto.
    eapply expr_eval_subseteq with Δ'' m τlr;
      eauto using indexes_valid_weaken, @sep_union_subseteq_l_transitive,
      @sep_union_subseteq_l', expr_typed_weaken.
Qed.
Lemma ax_var Γ δ A P Q x a :
  P ⊆{Γ} (Q (inl a) ∧ (A -★ var x ⇓ inl a))%A →
  Γ\ δ\ A ⊨ₑ {{ P }} var x {{ Q }}.
Proof.
  intros HQ Γ' Δ n ρ m [τ|] ?????? He ???; typed_inversion_all.
  match goal with H : _ !! x = _ |- _ => rewrite list_lookup_fmap in H end.
  destruct (ρ !! x) as [[o τ']|] eqn:?; decompose_Forall_hyps.
  apply ax_further_alt.
  intros Δ' n' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ Γ' Δ ρ n (cmap_erase m)) as [? HA]; eauto.
  destruct (HA Γ' Δ' n' mA) as (τlr&_&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  simplify_option_equality. typed_inversion_all.
  split; [solve_rcred|intros ? p _].
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  simplify_option_equality; apply mk_ax_next with Δ' m; auto.
  { constructor; auto. }
  { esolve_elem_of. }
  apply ax_done; constructor; eauto 9 using assert_weaken, addr_top_typed,
    indexes_valid_weaken, memenv_forward_typed, index_typed_valid.
Qed.
Lemma ax_rtol Γ δ A P Q1 Q2 e :
  (∀ v, Q1 (inr v) ⊆{Γ} (∃ a, Q2 (inl a) ∧ (A -★ .*#v ⇓ inl a))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} .* e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [τ|] ????? He1e2 He ???; typed_inversion_all.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ DCRtoL e ρ n m (inr (TType τ.* ))); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' [|v] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v Γ' Δ' ρ n' (cmap_erase m)) as (a'&?&HA);
    simpl; eauto 10 using indexes_valid_weaken.
  destruct (HA Γ' Δ'' n'' mA) as (τlr&?&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  destruct τlr as [τ'|]; simplify_option_equality; typed_inversion_all.
  assert (TType τ' = TType τ); [|simplify_equality].
  { apply typed_unique with (Γ',Δ'') a'; eauto using addr_typed_weaken. }
  assert (index_alive' (m ∪ mf ∪ mA) (addr_index a')).
  { apply cmap_subseteq_index_alive' with (mA ∪ cmap_erase m); auto.
    rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  split; [solve_rcred|intros ? p _].
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; auto.
  { constructor; auto. }
  { esolve_elem_of. }
  apply ax_done; constructor; eauto using addr_typed_weaken,
    assert_weaken, indexes_valid_weaken.
Qed.
Lemma ax_rofl Γ δ A P Q1 Q2 e :
  (∀ a, Q1 (inl a) ⊆{Γ} Q2 (inr (ptrV (Ptr a)))) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} & e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [τ|] ????? He1e2 He ???; typed_inversion_all.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ DCRofL e ρ n m (inl τ)); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' [a|] m ?????; typed_inversion_all.
  apply ax_further; [intros; solve_rcred|].
  intros Δ'' n'' ?? S' ??? Hframe p _; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; auto.
  { constructor; auto. } 
  { esolve_elem_of. }
  apply ax_done; constructor; eauto 7 using addr_typed_weaken.
  apply HQ; eauto using assert_weaken, indexes_valid_weaken.
Qed.
Lemma ax_load Γ δ A P Q1 Q2 e :
  (∀ a, Q1 (inl a) ⊆{Γ} (∃ v, Q2 (inr v) ∧ (A -★ load (%a) ⇓ inr v))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} load e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [|τ] ???????? HA HP; typed_inversion_all.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ DCLoad e ρ n m (inl τ)); auto.
  { esolve_elem_of. }
  clear dependent m. intros Δ' n' [a|] m ?????; typed_inversion_all.
  apply ax_further_alt; intros Δ'' n'' ????? Hframe;
    inversion_clear Hframe as [mA mf|]; simplify_equality.
  destruct (HQ a Γ' Δ' ρ n' (cmap_erase m))
    as (v&?&HA); eauto using indexes_valid_weaken.
  assert (⊥ [mA; cmap_erase m]).
  { rewrite <-cmap_erase_disjoint_le; auto. }
  destruct (HA Γ' Δ'' n'' mA) as (τlr&?&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  destruct τlr as [|τ']; simplify_option_equality; typed_inversion_all.
  assert (mA ∪ cmap_erase m ⊆ m ∪ mf ∪ mA).
  { rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  assert (⊥ [mA; cmap_erase m]).
  { rewrite <-cmap_erase_disjoint_le; auto. }
  assert ((m ∪ mf ∪ mA) !!{Γ'} a = Some v).
  { apply mem_lookup_subseteq with Δ'' (mA ∪ cmap_erase m); auto. }
  assert (mem_forced Γ' a (m ∪ mf ∪ mA)).
  { apply mem_forced_subseteq with Δ'' (mA ∪ cmap_erase m); eauto. }
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality|exfalso; eauto with cstep].
  rewrite mem_forced_force by auto.
  apply mk_ax_next with Δ'' m; simpl; auto.
  { constructor; auto. }
  assert (✓{Γ',Δ''} (m ∪ mf ∪ mA)) by eauto.
  apply ax_done; constructor; eauto using mem_lookup_typed,
    assert_weaken, indexes_valid_weaken, addr_typed_weaken.
Qed.
Definition assert_assign (a : addr K) (v : val K)
    (ass : assign) (τ : type K) (va v' : val K) : assert K :=
  match ass with
  | Assign => cast{τ} (#v) ⇓ inr va ∧ cast{τ} (#v) ⇓ inr v'
  | PreOp op =>
     cast{τ} (load (%a) @{op} #v) ⇓ inr va ∧
     cast{τ} (load (%a) @{op} #v) ⇓ inr v'
  | PostOp op =>
     cast{τ} (load (%a) @{op} #v) ⇓ inr va ∧
     load (%a) ⇓ inr v'
  end%A.
Lemma ax_assign Γ δ A P1 P2 Q1 Q2 Q ass e1 e2 μ γ τ :
  Some Writable ⊆ perm_kind γ →
  (∀ a v, (Q1 (inl a) ★ Q2 (inr v))%A ⊆{Γ} (∃ va v',
    (%a ↦{μ,γ} - : τ ★
    (%a ↦{μ,perm_lock γ} # (freeze true va) : τ -★ Q (inr v'))) ∧
    (A -★ assert_assign a v ass τ va v'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P1 }} e1 {{ Q1 }} → Γ\ δ\ A ⊨ₑ {{ P2 }} e2 {{ Q2 }} →
  Γ\ δ\ A ⊨ₑ {{ P1 ★ P2 }} e1 ::={ass} e2 {{ Q }}.
Proof.
  intros Hγ HQ Hax1 Hax2 Γ' Δ n ρ m
    [|τ1] ???? Hlock He ??? HP; [typed_inversion_all|].
  assert (Some Readable ⊆ perm_kind γ)by (by transitivity (Some Writable)).
  assert (∃ τ2, (Γ',Δ,ρ.*2) ⊢ e1 : inl τ1 ∧
    (Γ',Δ,ρ.*2) ⊢ e2 : inr τ2 ∧ assign_typed τ1 τ2 ass)
    as (τ2&?&?&?) by (typed_inversion_all; eauto); clear He.
  destruct HP as (m1'&m2'&Hm12&Hm12'&?&?).
  destruct (cmap_erase_union_inv m m1' m2') as (m1&m2&->&?&->&->); auto;
    simplify_mem_disjoint_hyps; clear Hm12 Hm12'.
  rewrite mem_locks_union in Hlock by auto; simpl in *; decompose_empty.
  apply (ax_expr_compose_2 Γ' δ A Q1 Q2 _ Δ (DCAssign ass) e1 e2 ρ n m1 m2
    (inl τ1) (inr τ2)); eauto using ax_expr_invariant_weaken,
    @sep_union_subseteq_l', @sep_union_subseteq_r'.
  { esolve_elem_of. }
  { esolve_elem_of. }
  clear dependent m1 m2; intros Δ' n' [a'|] [|v] m1' m2'
    ?????????; typed_inversion_all.
  apply ax_further_alt; intros Δ'' n'' ? ff ??? Hframe;
    inversion_clear Hframe as [mA mf|]; simplify_equality.
  destruct (HQ a' v Γ' Δ' ρ n' (cmap_erase (m1' ∪ m2')))
    as (va'&v'&(m1&m2''&?&?&(?&a&va&?&?&?&?&?)&HQ')&Hass);
    eauto 6 using indexes_valid_weaken; clear HQ.
  { rewrite cmap_erase_union.
    exists (cmap_erase m1') (cmap_erase m2'); split_ands; auto.
    by rewrite <-!cmap_erase_disjoint_le. }
  destruct (cmap_erase_union_inv_l (m1' ∪ m2') m1 m2'')
    as (m2&Hm&?&Hm'&->); auto; rewrite Hm in *;
    simplify_option_equality; typed_inversion_all.
  assert (TType τ = TType τ1); simplify_equality'.
  { eapply typed_unique with (Γ',Δ') a; eauto. }
  simplify_mem_disjoint_hyps.
  assert (mem_writable Γ' a (m1 ∪ m2 ∪ mf ∪ mA)).
  { eapply mem_writable_subseteq with Δ'' m1;
      eauto using mem_writable_singleton,
      @sep_union_subseteq_l_transitive, @sep_union_subseteq_l'. }
  assert (assign_sem Γ' (m1 ∪ m2 ∪ mf ∪ mA) a v ass va' v').
  { clear HQ'.
    assert (mA ∪ cmap_erase (m1 ∪ m2) ⊆ m1 ∪ m2 ∪ mf ∪ mA).
    { rewrite (sep_commutative _ mA) by auto.
      apply sep_preserving_l; auto using
        @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
    assert (⊥ [mA; cmap_erase (m1 ∪ m2)]).
    { rewrite <-cmap_erase_disjoint_le; auto. }
    eapply assign_sem_subseteq with Δ'' (mA ∪ cmap_erase (m1 ∪ m2)) τ1 τ2;
      eauto 15 using addr_typed_weaken, val_typed_weaken.
    destruct ass; destruct (Hass Γ' Δ'' n'' mA) as [(?&_&?) (?&_&?)];
      eauto 4 using assert_weaken, indexes_valid_weaken;
      clear Hass; simplify_option_equality;
      econstructor; simplify_type_equality; eauto. }
  clear Hass.
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality|exfalso; eauto 6 with cstep].
  match goal with
  | Hass : assign_sem _ ?m _ _ _ ?va'' ?v'' |- _ =>
    destruct (assign_sem_deterministic Γ' m a v ass va'' va' v'' v');
      auto; subst; clear Hass
  end.
  assert ((Γ',Δ'') ⊢ va' : τ1 ∧ (Γ',Δ'') ⊢ v' : τ1) as [].
  { eapply (assign_preservation _ _ (m1 ∪ m2 ∪ mf ∪ mA));
      eauto using addr_typed_weaken, val_typed_weaken. }
  assert (⊥ [<[a:=va']{Γ'}> m1; m2; mf; mA]).
  { by rewrite <-mem_insert_disjoint_le
      by eauto using mem_writable_singleton, addr_typed_weaken. }
  assert (✓{Γ',Δ''} (<[a:=va']{Γ'}> m1)).
  { eauto using mem_insert_valid, mem_writable_singleton, addr_typed_weaken. }
  assert (mem_writable Γ' a (<[a:=va']{Γ'}> m1)).
  { eauto 6 using mem_insert_writable,
      mem_writable_singleton, addr_typed_weaken. }
  assert (⊥ [mem_lock Γ' a (<[a:=va']{Γ'}> m1); m2; mf; mA]).
  { by rewrite <-mem_lock_disjoint_le by eauto using addr_typed_weaken. }
  assert (mem_locks (mem_lock Γ' a (<[a:=va']{Γ'}> m1) ∪ m2)
    = lock_singleton Γ' a ∪ mem_locks m1' ∪ mem_locks m2').
  { erewrite mem_locks_union, mem_locks_lock, mem_locks_insert
      by eauto using mem_writable_singleton, addr_typed_weaken.
    rewrite <-!(associative_L (∪)), <-mem_locks_union, Hm,
      mem_locks_union by auto; clear; solve_elem_of. }
  rewrite <-!(sep_associative m1) by auto.
  erewrite mem_insert_union, mem_lock_union
    by eauto using mem_writable_singleton, addr_typed_weaken.
  rewrite !sep_associative by auto.
  apply mk_ax_next with Δ'' (mem_lock Γ' a (<[a:=va']{Γ'}> m1) ∪ m2); simpl; auto.
  { constructor; auto. }
  { by apply reflexive_eq. } 
  { rewrite <-!sep_associative by auto; auto using mem_lock_valid. }
  apply ax_done; constructor; auto.
  rewrite cmap_erase_union,
    mem_erase_lock, mem_erase_insert, cmap_erased_spec by done.
  eapply HQ'; rewrite <-?cmap_erase_disjoint_le;
    eauto using cmap_erase_valid, mem_lock_valid.
  exists a (freeze true va'); split_ands;
    eauto using addr_typed_weaken, val_typed_weaken, val_typed_freeze.
  eauto using mem_lock_singleton, mem_insert_singleton, mem_singleton_weaken.
Qed.
Lemma ax_eltl Γ δ A P Q1 Q2 e rs :
  (∀ a, Q1 (inl a) ⊆{Γ} (∃ a', Q2 (inl a') ∧ (A -★ %a %> rs ⇓ inl a'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} e %> rs {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [σ|] ????? He ????; [|typed_inversion_all].
  assert (∃ τ, (Γ',Δ,ρ.*2) ⊢ e : inl τ ∧ Γ' ⊢ rs : τ ↣ σ) as (τ&?&?)
    by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ (DCEltL rs) e ρ n m (inl τ)); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' [a|] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ a Γ' Δ' ρ n' (cmap_erase m))
    as (a'&?&HA); eauto using indexes_valid_weaken.
  destruct (HA Γ' Δ'' n'' mA) as (τlr&?&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  destruct τlr as [τ'|]; simplify_option_equality; typed_inversion_all.
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; auto.
  { constructor; auto. }
  { esolve_elem_of. }
  apply ax_done; constructor; eauto using assert_weaken, addr_typed_weaken,
    indexes_valid_weaken, addr_elt_typed, addr_elt_strict.
Qed.
Lemma ax_eltr Γ δ A P Q1 Q2 e rs :
  (∀ v, Q1 (inr v) ⊆{Γ} (∃ v', Q2 (inr v') ∧ (A -★ #v #> rs ⇓ inr v'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} e #> rs {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [|σ] ????? He ????; [typed_inversion_all|].
  assert (∃ τ, (Γ',Δ,ρ.*2) ⊢ e : inr τ ∧ Γ' ⊢ rs : τ ↣ σ) as (τ&?&?)
    by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ (DCEltR rs) e ρ n m (inr τ)); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' [|v] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v Γ' Δ' ρ n' (cmap_erase m))
    as (v'&?&HA); eauto using indexes_valid_weaken.
  destruct (HA Γ' Δ'' n'' mA) as (τlr&?&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  destruct τlr as [|τ']; simplify_option_equality; typed_inversion_all.
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep;simplify_option_equality|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; auto.
  { constructor; auto. }
  { esolve_elem_of. }
  apply ax_done; constructor; eauto using assert_weaken,
    indexes_valid_weaken, val_typed_weaken, val_lookup_seg_typed.
Qed.
Lemma ax_insert Γ δ A P1 P2 Q1 Q2 R e1 e2 r :
  (∀ v1 v2,
    (Q1 (inr v1) ★ Q2 (inr v2))%A ⊆{Γ} (∃ v',
      R (inr v') ∧ (A -★ #[r:=#v1] (#v2) ⇓ inr v'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P1 }} e1 {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P2 }} e2 {{ Q2 }} →
  Γ\ δ\ A ⊨ₑ {{ P1 ★ P2 }} #[r:=e1] e2 {{ R }}.
Proof.
  intros HQ Hax1 Hax2 Γ' Δ n ρ m [|τ] ???? Hlocks He ??? HP;
    [typed_inversion_all|].
  assert (∃ σ, (Γ',Δ,ρ.*2) ⊢ e1 : inr σ ∧
    (Γ',Δ,ρ.*2) ⊢ e2 : inr τ ∧ Γ' ⊢ r : τ ↣ σ) as (σ&?&?&?)
    by (typed_inversion_all; eauto); clear He.
  destruct HP as (m1'&m2'&?&?&?&?).
  destruct (cmap_erase_union_inv m m1' m2')
    as (m1&m2&->&?&->&->); simplify_mem_disjoint_hyps; auto.
  rewrite mem_locks_union in Hlocks by auto; simpl in *; decompose_empty.
  apply (ax_expr_compose_2 Γ' δ A Q1 Q2 _ Δ (DCInsert r)
    e1 e2 ρ n m1 m2 (inr σ) (inr τ)); eauto using ax_expr_invariant_weaken,
    @sep_union_subseteq_l', @sep_union_subseteq_r'.
  { esolve_elem_of. }
  { esolve_elem_of. }
  clear dependent m1 m2.
  intros Δ' n' [|v1] [|v2] m1 m2 ?????????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v1 v2 Γ' Δ' ρ n' (cmap_erase (m1 ∪ m2)))
    as (v'&?&HA); eauto 6 using indexes_valid_weaken.
  { rewrite cmap_erase_union.
    exists (cmap_erase m1) (cmap_erase m2); split_ands; auto.
    by rewrite <-!cmap_erase_disjoint_le. }
  destruct (HA Γ' Δ'' n'' mA) as (?&_&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  simplify_option_equality; typed_inversion_all.
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality'|exfalso; eauto with cstep].
  rewrite <-mem_locks_union by auto.
  apply mk_ax_next with Δ'' (m1 ∪ m2); auto.
  { constructor; auto. }
  { simpl. by rewrite mem_locks_union by auto. }
  apply ax_done; constructor; eauto using assert_weaken,
    indexes_valid_weaken, val_typed_weaken, val_alter_const_typed.
Qed.
Lemma assert_alloc_params P Γ Δ ρ n m mf os vs τs :
  StackIndep P → ✓ Γ → ✓{Γ,Δ} m → m ⊥ mf → ✓{Δ}* ρ →
  (Γ,Δ) ⊢* vs :* τs → length os = length vs →
  Forall_fresh (dom indexset (m ∪ mf)) os →
  (dom indexset (mem_alloc_list Γ os vs (m ∪ mf)) ∖ dom indexset (m ∪ mf))
    ∩ dom indexset Δ = ∅ →
  assert_holds P Γ Δ [] n (cmap_erase m) → ∃ Δ',
  (**i 1.) *) Δ ⊆ Δ' ∧
  (**i 2.) *) (∀ Δ'',
    ✓{Γ,Δ''} (mem_alloc_list Γ os vs m) → Δ ⇒ₘ Δ'' → Δ' ⇒ₘ Δ'') ∧
  (**i 3.) *) ✓{Δ'}* (zip os τs) ∧
  (**i 4.) *) ✓{Γ,Δ'} (mem_alloc_list Γ os vs m) ∧
  (**i 5.) *) mem_alloc_list Γ os vs m ⊥ mf ∧
  (**i 6.) *) mem_alloc_list Γ os vs (m ∪ mf) = mem_alloc_list Γ os vs m ∪ mf ∧
  (**i 7.) *) assert_holds
    (Π imap2_go (λ i v τ,
      var i ↦{false,perm_full} #freeze true v : τ) (length ρ) vs τs ★ P)%A
    Γ Δ' (ρ ++ zip os τs) n (cmap_erase (mem_alloc_list Γ os vs m)).
Proof.
  intros ??; rewrite <-Forall2_same_length; intros Hm Hmmf Hρ Hvs Hos.
  revert Δ ρ τs Hm Hρ Hvs; induction Hos as [|o v os vs _ ? IH];
    intros Δ ρ [|τ τs]; inversion_clear 4; intros Hdom ?; decompose_Forall_hyps.
  { exists Δ; split_ands; auto. rewrite (right_id_L [] _).
    rapply (proj2 (left_id (R:=(≡{Γ})) emp (★) P)%A);
      eauto using stack_indep_spec. }
  rewrite mem_dom_alloc in Hdom.
  assert (Δ !! o = None).
  { apply not_elem_of_dom; clear IH; esolve_elem_of. }
  assert (Δ ⊆ <[o:=(τ,false)]>Δ) by (by apply insert_subseteq).
  assert (✓{Γ}(<[o:=(τ,false)]>Δ)) by eauto 3 using mem_alloc_memenv_valid,
    cmap_valid_memenv_valid, val_typed_type_valid.
  assert (<[o:=(τ,false)]> Δ ⊢ o : τ) by (by apply mem_alloc_index_typed).
  destruct (IH (<[o:=(τ,false)]>Δ) (ρ ++ [(o,τ)]) τs)
    as (Δ'&?&Hleast&?&?&?&->&HP);
    eauto using assert_weaken, Forall2_impl, val_typed_weaken,
    cmap_valid_weaken, indexes_valid_weaken; clear IH.
  { rewrite mem_dom_alloc_list in Hdom |- * by eauto using Forall2_length.
    rewrite dom_insert_L; esolve_elem_of. }
  assert (Δ ⊆ Δ') by (by transitivity (<[o:=(τ, false)]> Δ)).
  assert (o ∉ dom indexset m ∧ o ∉ dom indexset mf) as [??].
  { by rewrite <-not_elem_of_union, <-cmap_dom_union. }
  assert (o ∉ dom indexset (mem_alloc_list Γ os vs m)).
  { by rewrite mem_dom_alloc_list, not_elem_of_union, elem_of_of_list
      by eauto using Forall2_length. }
  assert (Δ' ⊢ o : τ)
    by eauto using memenv_forward_typed, memenv_subseteq_forward.
  assert (✓{Γ,Δ'} (mem_alloc Γ o false perm_full v (mem_alloc_list Γ os vs m))).
  { eapply mem_alloc_alive_valid; eauto using val_typed_weaken,
      memenv_subseteq_alive, mem_alloc_index_alive. }
  exists Δ'; split_ands; eauto using mem_alloc_disjoint, mem_alloc_union.
  { intros Δ'' ??; transitivity (<[o:=(τ,false)]> Δ').
    { by rewrite (insert_id Δ' o (τ,false))
        by (by apply lookup_weaken with (<[o:=(τ,false)]> Δ); simpl_map). }
    eapply mem_alloc_forward_least, Hleast;
      eauto using val_typed_weaken, mem_alloc_valid_inv.
    destruct (mem_alloc_valid_index_inv Γ Δ'' (mem_alloc_list Γ os vs m) o
      false perm_full v) as [[??] [??]]; auto; simplify_type_equality.
    rewrite <-(insert_id Δ'' o (τ,false)) by done.
    by apply mem_alloc_memenv_compat. }
  rapply (λ P Q R : assert K, proj1 (associative (R:=(≡{Γ})) (★)%A P Q R));
    eauto using indexes_valid_weaken.
  rewrite <-(associative_L (++)), app_length, Nat.add_1_r in HP.
  destruct (mem_alloc_singleton Γ Δ' (mem_alloc_list Γ os vs m) o
    false perm_full v τ) as (m'&->&?&?); eauto using val_typed_weaken,
    memenv_subseteq_alive, mem_alloc_index_alive;
    simplify_mem_disjoint_hyps.
  erewrite cmap_erase_union, mem_erase_singleton by eauto.
  exists m' (cmap_erase (mem_alloc_list Γ os vs m)); split_ands; csimpl;
    eauto using assert_weaken, mem_alloc_forward.
  { by rewrite <-cmap_erase_disjoint_le. }
  eexists (addr_top o τ), (freeze true v); split_ands; auto.
  * typed_constructor. by rewrite fmap_app,
      fmap_cons, list_lookup_middle by (by rewrite fmap_length).
  * by simpl; rewrite list_lookup_middle by done.
  * typed_constructor; eauto using val_typed_weaken, val_typed_freeze.
Qed.
Lemma assert_free_params P Γ Δ ρ n m mf os τs :
  StackIndep P → ✓ Γ → ✓{Γ,Δ} (m ∪ mf) → m ⊥ mf → ✓{Δ}* ρ → ✓{Δ}* (zip os τs) →
  assert_holds (Π imap_go (λ i τ, var i ↦{false,perm_full} - : τ)
    (length ρ) τs ★ P)%A Γ Δ (ρ ++ zip os τs) n (cmap_erase m) →
  length os = length τs → NoDup os → ∃ Δ',
  (**i 1.) *) Δ ⇒ₘ Δ' ∧
  (**i 2.) *) (∀ Δ'', ✓{Γ,Δ''} (foldr mem_free m os) → Δ ⇒ₘ Δ'' → Δ' ⇒ₘ Δ'') ∧
  (**i 3.) *) ✓{Γ,Δ'} (foldr mem_free m os ∪ mf) ∧
  (**i 5.) *) foldr mem_free m os ⊥ mf ∧
  (**i 4.) *) foldr mem_free (m ∪ mf) os = foldr mem_free m os ∪ mf ∧
  (**i 6.) *) mem_locks (foldr mem_free m os) = mem_locks m ∧
  (**i 7.) *) assert_holds P Γ Δ' ρ n (cmap_erase (foldr mem_free m os)).
Proof.
  intros ?? Hm Hmmf Hρ Hoτs HP; rewrite <-Forall2_same_length; intros Hos.
  revert Δ ρ m Hρ Hoτs Hm Hmmf HP.
  induction Hos as [|o τ os τs ? _ IH]; intros Δ ρ m ???? HP;
    inversion_clear 1; decompose_Forall_hyps; simplify_mem_disjoint_hyps.
  { rewrite (right_id_L [] _) in HP; exists Δ; split_ands; auto.
    rapply (proj1 (left_id (R:=(≡{Γ})) emp (★) P)%A); auto. }
  assert (assert_holds (var (length ρ) ↦{false,perm_full} - : τ ★
    Π imap_go (λ i τ, (var i ↦{false,perm_full} - : τ)%A) (S (length ρ)) τs ★ P)
    Γ Δ (ρ ++ (o, τ) :: zip os τs) n (cmap_erase m))
    as (m1&m2'&?&?&(?&?&v&_&Heval&_&?&?)&?); csimpl in *; [|clear HP].
  { rapply (λ P Q R : assert K,
      proj2 (associative (R:=(≡{Γ})) (★)%A P Q R)); auto. }
  rewrite list_lookup_middle in Heval by done; simplify_option_equality.
  destruct (cmap_erase_union_inv_l m m1 m2') as (m2&->&?&_&->); auto.
  simplify_mem_disjoint_hyps.
  assert (mem_freeable_perm o false m1)
    by eauto using mem_freeable_perm_singleton.
  assert (mem_freeable_perm o false (m1 ∪ m2))
    by eauto using mem_freeable_perm_subseteq, @sep_union_subseteq_l.
  destruct (IH (alter (prod_map id (λ _, true)) o Δ) (ρ ++ [(o,τ)])
    (mem_free o (m1 ∪ m2))) as (Δ'&?&Hleast&?&?&?&Hlocks&?);
    eauto using indexes_valid_weaken, mem_free_forward, mem_free_disjoint.
  { erewrite <-mem_free_union by eauto; eauto. }
  { erewrite mem_free_union, cmap_erase_union, mem_free_singleton,
      sep_left_id, <-(associative_L (++)), app_length, Nat.add_1_r by eauto.
    eauto 10 using assert_weaken, mem_free_forward. }
  simplify_mem_disjoint_hyps.
  assert (Δ ⇒ₘ Δ').
  { transitivity (alter (prod_map id (λ _, true)) o Δ);
      auto using mem_free_forward. }
  rewrite !mem_free_foldr_free; exists Δ'; split_ands; auto.
  * intros Δ'' Hvalid ?; apply Hleast; auto.
    assert (∀ τ', Δ'' !! o = Some (τ',false) → False).
    { intros τ' ?; destruct (mem_free_valid_index_inv Γ Δ''
        (foldr mem_free (m1 ∪ m2) os) false o); rewrite ?mem_free_foldr_free;
        auto using mem_freeable_perm_foldr_free.
      by exists τ'. }
    rewrite <-(alter_id (prod_map id (λ _, true)) Δ'' o)
      by (intros [? []] ?; naive_solver); eauto using mem_free_memenv_compat.
  * by erewrite mem_free_union by eauto.
  * by erewrite Hlocks, mem_locks_free by eauto.
  * apply stack_indep_spec with (ρ ++ [(o, τ)]);
      eauto using indexes_valid_weaken.
Qed.
Lemma assert_fun_intro Γ δ (f : funname) Pf τs τ :
  Γ !! f = Some (τs,τ) →
  (∀ s c vs,
    δ !! f = Some s →
    Γ\ δ ⊨ₛ {{ Π imap2 (λ i v τ,
                 var i ↦{false,perm_full} #freeze true v : τ) vs τs ★
               fpre Pf c vs }}
              s
            {{ λ v, Π imap (λ i τ, var i ↦{false,perm_full} - : τ) τs ★
                    fpost Pf c vs v }}) →
  emp%A ⊆{Γ} assert_fun δ f Pf τs τ.
Proof.
  intros ? Hf Γ1 Δ1 ρ n1 m ???? [_ ->].
  split_ands'; eauto using lookup_fun_weaken.
  intros Γ2 Δ2 n2 c vs m ?????????.
  apply ax_further_alt; intros Δ3 n3 ? mf ??? (->&?&?).
  destruct (funenv_lookup Γ2 Δ2 δ f τs τ) as (s&cmτ&?&_&?&_);
    eauto using lookup_fun_weaken.
  assert (✓{Δ2}* ρ) by eauto using indexes_valid_weaken.
  clear dependent Δ1 n1.
  split; [solve_rcred|intros S p Hdom].
  assert (∃ os, Forall_fresh (dom indexset (m ∪ mf)) os ∧
    length os = length vs ∧
    S = State [CParams f (zip os (type_of <$> vs))]
              (Stmt ↘ s) (mem_alloc_list Γ2 os vs (m ∪ mf)))
    as (os&?&?&->) by (inv_rcstep p; eauto);
    clear p; simplify_type_equality'.
  erewrite fmap_type_of by eauto.
  destruct (assert_alloc_params (fpre Pf c vs) Γ2 Δ3 [] n3 m mf os vs τs)
    as (Δ4&?&?&?&?&?&->&Hpre); eauto using Forall2_impl, val_typed_weaken,
    assert_weaken, indexes_valid_weaken.
  apply mk_ax_next with Δ4 (mem_alloc_list Γ2 os vs m); auto.
  { constructor; auto. }
  { eauto using cmap_union_valid_2, cmap_valid_weaken. }
  { intros; simplify_mem_disjoint_hyps; eauto. }
  destruct (funenv_lookup Γ2 Δ2 δ f τs τ) as (?&τlr&?&?&?&?&?&?);
    eauto using lookup_fun_weaken; simplify_equality.
  assert (length os = length τs).
  { erewrite <-(Forall2_length _ _ τs) by eauto; lia. }
  assert (NoDup os)
    by (by apply Forall_fresh_NoDup with (dom indexset (m ∪ mf))).
  eapply ax_compose_cons with ax_disjoint_cond _; eauto.
  { eapply Hf, Hpre; eauto using funenv_valid_weaken.
    * by transitivity Γ1.
    * assert (Forall_fresh (dom indexset m) os).
      { eapply Forall_fresh_subseteq; eauto.
        rewrite cmap_dom_union; solve_elem_of. }
      by erewrite mem_locks_alloc_list by eauto.
    * simpl; rewrite snd_zip by lia; eauto using stmt_typed_weaken. }
  clear dependent m mf; intros Δ5 n4 ? m; destruct 1; intros.
  apply ax_further_alt; intros Δ6 n5 ? mf ??? (->&?&?).
  split; [solve_rcred|intros S p _].
  assert (∃ v, S = State [] (Return f v) (foldr mem_free (m ∪ mf) os) ∧
    assert_holds (Π imap (λ i τ, (var i ↦{false,perm_full} - : τ)%A) τs
      ★ fpost Pf c vs v) Γ2 Δ5 (zip os τs) n4 (cmap_erase m) ∧
    (Γ2,Δ5) ⊢ v : τ) as (v&->&?&?).
  { inv_rcstep; typed_inversion_all;
      match goal with H : rettype_match _ _ |- _ => inversion H; subst end;
      eexists; split_ands; rewrite ?fst_zip by auto; eauto. }
  clear dependent p d.
  destruct (assert_free_params (fpost Pf c vs v) Γ2 Δ6 [] n5 m mf os τs)
    as (Δ7&?&?&?&?&->&?&?); eauto using assert_weaken, indexes_valid_weaken.
  apply mk_ax_next with Δ7 (foldr mem_free m os); auto.
  { constructor; auto. }
  { intros; simplify_mem_disjoint_hyps; eauto. }
  apply ax_done; constructor; eauto using val_typed_weaken with congruence.
Qed.
Lemma ax_call {vn} Γ δ A Pf P Q Ps Qs R e (es : vec (expr K) vn) τs τ c :
  (∀ v vs,
    (A ★ Q (inr v) ★ Π vzip_with (λ Q v, Q (inr v)) Qs vs)%A ⊆{Γ} (∃ f,
      ⌜ v = ptrV (FunPtr f τs τ) ⌝ ★ 
      ▷ (assert_fun δ f Pf τs τ) ★ fpre Pf c vs ★
      (∀ vret, fpost Pf c vs vret -★ (A ★ R (inr vret))))%A) →
  Γ\ δ \ A ⊨ₑ {{ P }} e {{ λ ν, (Q ν) ◊ }} →
  (∀ i, Γ\ δ\ A ⊨ₑ {{ Ps !!! i }} es !!! i {{ λ ν, ((Qs !!! i) ν) ◊ }}) →
  Γ\ δ \ A ⊨ₑ {{ P ★ Π Ps }} call e @ es {{ R }}.
Proof.
  intros HQ Hax1 Hax2 Γ' Δ n ρ m τlr ????? He ??? HP.
  assert (∃ τ (τs : vec _ vn), τlr = inr τ ∧
    (Γ',Δ,ρ.*2) ⊢ e : inr ((τs ~> τ).*) ∧
    ∀ i, (Γ',Δ,ρ.*2) ⊢ es !!! i : inr (τs !!! i))
    as (τ'&τs'&->&?&?); [|clear He].
  { assert (∃ τ τs, τlr = inr τ ∧ (Γ',Δ,ρ.*2) ⊢ e : inr ((τs ~> τ).*) ∧
      (Γ',Δ,ρ.*2) ⊢* es :* inr <$> τs) as (τ'&τs'&->&?&Hes)
      by (typed_inversion_all; eauto).
    assert (vn = length τs') by (by erewrite <-fmap_length,
      <-Forall2_length, vec_to_list_length by eauto); subst vn.
    exists τ' (list_to_vec τs'). rewrite ?vec_to_list_of_list.
    by rewrite Forall2_fmap_r, <-(vec_to_list_of_list τs'),
      Forall2_vlookup in Hes. }
  destruct HP as (m1'&m2&Hm&Hm'&?&HPs).
  destruct (cmap_erase_union_inv_r m m1' m2)
    as (m1&->&?&->&?); simplify_mem_disjoint_hyps; auto; clear Hm Hm'.
  rewrite assert_Forall_holds_vec in HPs; destruct HPs as (ms&->&?&?).
  repeat match goal with
    | _ => progress simpl in *
    | H : mem_locks (_ ∪ _) = ∅ |- _ => rewrite mem_locks_union in H by auto
    | H : mem_locks (⋃ _) = ∅ |- _ => rewrite mem_locks_union_list in H by auto
    | H : ✓{_} (⋃ _) |- _ =>
       rewrite <-cmap_union_list_valid, Forall_vlookup in H by eauto
    | H : _ ∪ _ = ∅ |- _ => apply empty_union_L in H; destruct H
    | H : ⋃ _ = ∅ |- _ =>
       rewrite empty_union_list_L, Forall_fmap, Forall_vlookup in H
    end.
  apply (ax_expr_compose Γ' δ A ((λ ν, Q ν ◊)%A ::: vmap (λ Q ν, Q ν ◊)%A Qs) R
    Δ (DCCall vn) (e ::: es) ρ n
    (m1 ::: ms) (inr ((τs' ~> τ').*) ::: vmap inr τs')); auto.
  { intros i; inv_fin i; eauto. }
  { intros i; inv_fin i; esolve_elem_of. }
  { intros i; inv_fin i; simpl.
    { eauto using ax_expr_invariant_weaken, @sep_union_subseteq_l'. }
    intros i; rewrite vlookup_map; eapply Hax2; eauto.
    * by rewrite vlookup_map.
    * eapply ax_expr_invariant_weaken; eauto.
      by apply sep_union_subseteq_r_transitive, (sep_subseteq_lookup ms).
    * by rewrite cmap_erased_spec
        by eauto using cmap_erased_subseteq, (sep_subseteq_lookup ms). }
  clear dependent m1 ms e es P Ps; intros Δ' n' νs ms.
  inv_vec νs; intros ν νs; inv_vec ms; intros m ms.
  intros ? Hms ?? Hνs HQs;
    repeat match goal with
    | H : ∀ i : fin (S _), _ |- _ =>
       pose proof (H 0%fin); specialize (λ i, H (FS i)); simpl in *
    | H : assert_holds _ _ _ _ _ _ |- _ => rewrite assert_unlock_spec in H
    end.
  destruct ν as [|v]; typed_inversion_all.
  assert (∃ vs, νs = vmap inr vs ∧ (Γ',Δ') ⊢* vs :* τs') as (vs&->&Hvs).
  { revert Hνs; clear; induction νs as [|ν ? νs IH].
    { inv_vec τs'; eexists [#]; simpl; auto. }
    inv_vec τs'; intros τ τs Hi; destruct (IH τs (λ i, Hi (FS i))) as (vs&->&?).
    specialize (Hi 0%fin); typed_inversion_all; eexists (_:::_); simpl; eauto. }
  clear Hνs.
  rewrite vec_to_list_zip_with, vec_to_list_map, zip_with_fmap_r.
  rewrite <-(zip_with_fmap_l (λ Ω v, #{Ω} v)%E mem_locks).
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf ?????? HmA|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v vs Γ' Δ'' ρ (S n'')
    (cmap_erase (mem_unlock_all (m ∪ ⋃ ms ∪ mA))))
    as (f&?&?&Hm&_&[-> ->]&?&?&->&_&Hf&m''&mf2&->&?&?&Hpost); clear HQ;
    eauto using indexes_valid_weaken, mem_unlock_all_valid.
  { assert (⊥ (mA :: cmap_erase m :: cmap_erase <$> vec_to_list ms)).
    { rewrite <-cmap_erase_disjoint_le, <-cmap_erase_disjoint_list_le; auto. }
    rewrite (sep_commutative _ mA), mem_erase_unlock_all by auto.
    rewrite !cmap_erase_union,
      cmap_erase_union_list, (cmap_erased_spec mA) by auto.
    rewrite !mem_unlock_all_union,
      mem_unlock_all_union_list, (mem_unlock_all_empty_locks mA) by auto.
    assert (⊥ (mA :: mem_unlock_all (cmap_erase m) ::
      mem_unlock_all <$> cmap_erase <$> vec_to_list ms)) by
      by rewrite <-mem_unlock_all_disjoint_le,<-mem_unlock_all_disjoint_list_le.
    eexists mA, _; split_ands; auto.
    eexists _, _; split_ands;
      eauto using assert_weaken, indexes_valid_weaken, mem_unlock_all_valid.
    apply assert_Forall_holds_2; auto.
    rewrite <-!vec_to_list_map, Forall2_vlookup; intros i; specialize (HQs i).
    rewrite !vlookup_map, vlookup_zip_with.
    rewrite !vlookup_map, assert_unlock_spec in HQs; simpl in *.
    eauto using assert_weaken, indexes_valid_weaken, mem_unlock_all_valid. }
  destruct (Hf n'') as (->&?&Hf'); clear Hf; auto.
  rewrite !sep_left_id in Hm by auto; typed_inversion_all.
  assert (⊥ [mem_unlock_all (m ∪ ⋃ ms ∪ mA); mf])
    by (rewrite <-mem_unlock_all_disjoint_le; auto).
  destruct (cmap_erase_union_inv_r (mem_unlock_all (m ∪ ⋃ ms ∪ mA)) m'' mf2)
    as (m'&Hm'&?&->&?); auto.
  assert (mem_locks m' = ∅ ∧ mem_locks mf2 = ∅) as [??].
  { rewrite <-empty_union_L, <-mem_locks_union, <-Hm' by auto.
    by rewrite mem_locks_unlock_all. }
  assert (✓{Γ',Δ''} (mem_unlock_all (m ∪ ⋃ ms ∪ mA)))
    by eauto using mem_unlock_all_valid.
  assert (✓{Γ',Δ''} m' ∧ ✓{Γ',Δ''} mf2) as [??].
    by (rewrite <-cmap_union_valid, <-Hm' by auto; auto).
  assert (length (mem_locks <$> vec_to_list ms) = length vs).
  { rewrite fmap_length; apply vec_to_list_same_length. }
  split; [solve_rcred|intros ? p _].
  apply (rcstep_expr_call_inv _ _ _ _ _ _ _ _ _ _ _ _ p); auto; clear p.
  assert (mem_locks (m ∪ ⋃ ms ∪ mA) =
    mem_locks m ∪ ⋃ (mem_locks <$> vec_to_list ms)).
  { rewrite !mem_locks_union, mem_locks_union_list by auto.
    by rewrite HmA, (right_id_L _ _). }
  rewrite <-sep_associative, (sep_commutative mf), sep_associative by auto.
  rewrite mem_unlock_union, <-mem_unlock_all_spec_alt
    by eauto using (reflexive_eq (R:=(⊆) : relation lockset)), eq_sym.
  apply mk_ax_next with Δ'' (mem_unlock_all (m ∪ ⋃ ms ∪ mA)); auto.
  { apply ax_unframe_expr_to_fun with (mem_unlock_all (m ∪ ⋃ ms)); auto.
    * by rewrite mem_unlock_all_union, (mem_unlock_all_empty_locks mA) by auto.
    * rewrite mem_unlock_all_union, (mem_unlock_all_empty_locks mA) by auto.
      by rewrite <-!sep_associative, (sep_commutative mA)
        by (rewrite <-?mem_unlock_all_disjoint_le; auto).
    * rewrite <-mem_unlock_all_disjoint_le; auto. }
  rewrite Hm'; clear dependent m ms mA mf S'.
  eapply ax_compose_cons with ax_disjoint_cond
    (ax_fun_post f τ' (λ v, fpost Pf c vs v ★ assert_eq_mem mf2)%A); auto.
  { apply ax_frame with ax_disjoint_cond (ax_fun_post f τ' (fpost Pf c vs));
      auto using ax_disjoint_cond_frame_diagram.
    apply Hf'; eauto using funenv_valid_weaken, Forall2_impl, val_typed_weaken.
    { eapply stack_indep_spec with ρ;
        eauto using assert_weaken, indexes_valid_weaken. }
    intros Δ''' n''' ? m'' ?????; destruct 1; constructor; auto.
    * by rewrite mem_locks_union, empty_union_L by auto.
    * rewrite cmap_erase_union, (cmap_erased_spec mf2) by auto.
      exists (cmap_erase m) mf2; split_ands; try done.
      by rewrite <-cmap_erase_disjoint_le. }
  clear dependent m' Hf'.
  intros Δ''' n''' m'; destruct 1 as [v m''' ?? (m''&?&?&?&?&Hmf)]; intros.
  repeat red in Hmf; subst. 
  destruct (cmap_erase_union_inv_r m''' m'' mf2) as (m&->&?&->&?); auto.
  apply ax_further_alt; intros Δ'''' n'''';
    destruct 4; simplify_equality'; simplify_mem_disjoint_hyps.
  split; [solve_rcred|intros S' p _; inv_rcstep p].
  destruct (Hpost v Γ' Δ'''' (S n'''') (cmap_erase m))
    as (mA&m''&?&?&?&?); auto.
  { eapply stack_indep_spec with [];
      eauto using assert_weaken, indexes_valid_weaken. }
  destruct (cmap_erase_union_inv_l (m ∪ mf2) mA m'')
    as (m'&Hm'&?&?&->); auto.
  { by rewrite cmap_erase_union, (cmap_erased_spec mf2) by auto. }
  assert (⊥ [mA ∪ m'; mf]) by (rewrite <-Hm'; auto).
  assert (mem_locks mA = ∅ ∧ mem_locks m' = ∅) as [??].
  { by rewrite <-empty_union_L, <-mem_locks_union, <-Hm' by auto. }
  assert (✓{Γ',Δ''''} mA ∧ ✓{Γ',Δ''''} m') as [??].
  { rewrite <-cmap_union_valid, <-Hm' by auto; auto. }
  assert (mem_locks mA = ∅ ∧ mem_locks m' = ∅) as [??].
  { by rewrite <-empty_union_L, <-mem_locks_union, <-Hm' by auto. }
  rewrite Hm', <-sep_associative, (sep_commutative mA) by auto.
  apply mk_ax_next with Δ'''' m'; simpl; auto.
  { apply ax_unframe_fun_to_expr with mA; auto. }
  { apply subseteq_empty. }
  apply ax_done; constructor; eauto 7 using val_typed_weaken,
    assert_weaken, indexes_valid_weaken.
Qed.
Lemma ax_alloc Γ δ A P Q1 Q2 e τ :
  (∀ o vb,
    Q1 (inr (VBase vb)) ⊆{Γ} (∃ n τi,
      ⌜ vb = (intV{τi} n)%B ∧ Z.to_nat n ≠ 0 ⌝ ★
      ((% (addr_top o (τ.[Z.to_nat n])) ↦{true,perm_full} - : (τ.[Z.to_nat n]) -★
         Q2 (inr (ptrV (Ptr (addr_top_array o τ n))))) ∧
       (⌜ alloc_can_fail ⌝ -★ Q2 (inr (ptrV (NULL (TType τ)))))))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} alloc{τ} e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m τlr ????? He ????.
  assert (∃ τi, (Γ',Δ,ρ.*2) ⊢ e : inr (intT τi) ∧
    ✓{Γ'} τ ∧ τlr = inr (TType τ.*)) as (τi&?&?&->)
    by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ
    (DCAlloc τ) e ρ n m (inr (intT τi))); auto.
  { esolve_elem_of. }
  clear dependent m.
  intros Δ' n' [|[vb| | | |]] m ?????; typed_inversion_all.
  destruct (HQ (fresh ∅) vb Γ' Δ' ρ n' (cmap_erase m)) as
    (na&τi'&?&?&Hm&Hm'&[[-> ?] ->]&[_ Hfail]); eauto using indexes_valid_weaken;
    typed_inversion_all.
  rewrite sep_left_id in Hm by auto; simplify_equality; clear Hm'.
  apply ax_further; [intros; solve_rcred|].
  intros Δ'' n'' ?? S' ??? Hframe p Hdom; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  assert (alloc_can_fail ∧
    S' = State [] (Expr (#{mem_locks m} ptrV (NULL (TType τ)))) (m ∪ mf ∪ mA)
    ∨ ∃ o,
      S' = State [] (Expr (#{mem_locks m} ptrV (Ptr (addr_top_array o τ na))))
        (mem_alloc Γ' o true perm_full (val_new Γ' (τ.[Z.to_nat na]))
        (m ∪ mf ∪ mA)) ∧ o ∉ dom indexset (m ∪ mf ∪ mA))
    as [[? ->]|(o&->&Ho)]; [| |simplify_equality'; clear Hfail p].
  { inv_rcstep p; [inv_ehstep;eauto|exfalso; eauto with cstep]. }
  { econstructor; simpl; eauto; [constructor; eauto|].
    apply ax_done; constructor; eauto 10 using type_valid_ptr_type_valid.
    assert (⊥ [∅; cmap_erase m]).
    { rewrite <-cmap_erase_disjoint_le; auto. }
    rewrite <-(sep_left_id (cmap_erase m)) by auto; by eapply Hfail; eauto. }
  assert (Δ'' !! o = None); [|clear Hdom].
  { rewrite mem_dom_alloc in Hdom. apply not_elem_of_dom; esolve_elem_of. }
  rewrite <-sep_associative, cmap_dom_union,
    not_elem_of_union in Ho by auto; destruct Ho.
  assert (✓{Γ'} (τ.[Z.to_nat na])) by eauto using TArray_valid.
  assert (
    mem_alloc Γ' o true perm_full (val_new Γ' (τ.[Z.to_nat na])) m ⊥ mf ∪ mA)
    by eauto using (mem_alloc_disjoint _ Δ'); simplify_mem_disjoint_hyps.
  apply mk_ax_next with (<[o:=(τ.[Z.to_nat na],false)]>Δ'')
    (mem_alloc Γ' o true perm_full (val_new Γ' (τ.[Z.to_nat na])) m);
    eauto using mem_alloc_forward, mem_alloc_forward_least.
  { rewrite <-sep_associative, !mem_alloc_union, sep_associative by auto.
    constructor; auto. }
  { simpl. by erewrite (mem_locks_alloc _ Δ'') by eauto. }
  apply ax_done; constructor; eauto 8 using addr_top_array_typed,
    mem_alloc_index_typed, (mem_locks_alloc _ Δ'').
  destruct (mem_alloc_singleton_alt Γ' Δ'' m o true perm_full
    (val_new Γ' (τ.[Z.to_nat na])) (τ.[Z.to_nat na]))
    as (m'&Hm'&?&?); auto using val_new_frozen.
  rewrite Hm' in *; simplify_mem_disjoint_hyps; clear Hm'.
  erewrite cmap_erase_union, mem_erase_singleton by eauto.
  destruct (HQ o (intV{τi} na)%B Γ' Δ' ρ n' (cmap_erase m))
    as (na'&τi''&_&m''&Hm''&?&[[? _] ->]&HQ2); eauto using indexes_valid_weaken.
  rewrite sep_left_id in Hm'' by auto; simplify_equality'.
  eapply HQ2; eauto using mem_alloc_forward, indexes_valid_weaken; clear HQ2.
  { by eapply mem_singleton_valid;
      eauto using mem_alloc_memenv_valid, mem_alloc_index_alive. }
  { eauto using cmap_valid_weaken,
      (insert_subseteq Δ''), mem_alloc_memenv_valid. }
  { by rewrite <-cmap_erase_disjoint_le. }
  eexists _, (addr_top o (τ.[Z.to_nat na'])), (val_new Γ' (τ.[Z.to_nat na']));
    split_ands; eauto using addr_top_typed, mem_alloc_index_typed.
Qed.
Lemma ax_free Γ δ A P Q1 Q2 e τ :
  (∀ a,
    Q1 (inl a) ⊆{Γ} (∃ n,
      ⌜ addr_is_top_array a ⌝ ★
      % addr_top (addr_index a) (τ.[n]) ↦{true,perm_full} - : (τ.[n]) ★
      Q2 (inr voidV))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} free e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m τlr ????? He ????.
  assert (∃ τ', (Γ',Δ,ρ.*2) ⊢ e : inl τ' ∧ τlr = inr voidT) as (τ'&?&->)
    by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ DCFree e ρ n m (inl τ')); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' [a|] m ?????; typed_inversion_all.
  destruct (HQ a Γ' Δ' ρ n' (cmap_erase m))
    as (na&?&?&Hm'&?&[Ha' ->]&m1&m2'&?&?&(ν&a'&v&_&?&?&?&?)&?);
    eauto using indexes_valid_weaken.
  rewrite sep_left_id in Hm' by auto;
    simplify_option_equality; typed_inversion_all.
  destruct (cmap_erase_union_inv_l m m1 m2')
    as (m2&->&Hm12'&_&->); auto; simplify_mem_disjoint_hyps.
  assert (∀ mf mA, ⊥ [m1; m2; mf; mA] → mem_freeable a (m1 ∪ m2 ∪ mf ∪ mA)).
  { split; eauto using (mem_freeable_perm_singleton _ Δ').
    eapply mem_freeable_perm_subseteq; eauto using mem_freeable_perm_singleton,
      @sep_union_subseteq_l', @sep_union_subseteq_l_transitive. }
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
      simplify_equality; simplify_mem_disjoint_hyps.
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  match goal with H : mem_freeable _ _ |- _ => destruct H end.
  assert (mem_freeable_perm (addr_index a) true m1)
    by eauto using mem_freeable_perm_singleton.
  assert (⊥ [mem_free (addr_index a) m1; m2; mf; mA])
    by (by rewrite <-mem_free_disjoint_le by eauto).
  apply mk_ax_next with
    (alter (prod_map id (λ _, true)) (addr_index a) Δ'')
    (mem_free (addr_index a) (m1 ∪ m2));
    eauto using mem_free_forward, mem_free_forward_least.
  { erewrite <-!(sep_associative m1), !mem_free_union by eauto.
    rewrite !sep_associative by eauto; constructor; auto. }
  { simpl. by erewrite mem_locks_free
      by eauto using mem_freeable_perm_subseteq, @sep_union_subseteq_l'. }
  apply ax_done; constructor; eauto.
  { by erewrite mem_locks_free
      by eauto using mem_freeable_perm_subseteq, @sep_union_subseteq_l'. }
  erewrite mem_free_union, cmap_erase_union, mem_free_singleton, sep_left_id
    by eauto using mem_freeable_perm_singleton.
  eauto using assert_weaken, mem_free_forward, indexes_valid_weaken.
Qed.
Lemma ax_unop Γ δ A P Q1 Q2 op e :
  (∀ v, Q1 (inr v) ⊆{Γ} (∃ v', Q2 (inr v') ∧ (A -★ @{op} #v ⇓ inr v'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} @{op} e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [|σ] ????? He ?? HA HP; [typed_inversion_all|].
  assert (∃ τ, (Γ',Δ,ρ.*2) ⊢ e : inr τ ∧ unop_typed op τ σ)
    as (τ&?&?) by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ (DCUnOp op) e ρ n m (inr τ)); auto.
  { esolve_elem_of. }
  clear dependent m. intros Δ' n' [a|] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v Γ' Δ' ρ n' (cmap_erase m))
    as (v'&?&HA); eauto using indexes_valid_weaken.
  destruct (HA Γ' Δ'' n'' mA) as (?&_&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  simplify_option_equality.
  assert (val_unop_ok (m ∪ mf ∪ mA) op v).
  { eapply val_unop_ok_weaken with (mA ∪ cmap_erase m); eauto.
    intros; eapply cmap_subseteq_index_alive; eauto.
    rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; simpl; auto.
  { constructor; auto. }
  apply ax_done; constructor; eauto using mem_lookup_typed,
    indexes_valid_weaken, assert_weaken, val_unop_typed, val_typed_weaken.
Qed.
Lemma ax_binop Γ δ A P1 P2 Q1 Q2 R op e1 e2 :
  (∀ v1 v2,
    (Q1 (inr v1) ★ Q2 (inr v2))%A ⊆{Γ} (∃ v,
      R (inr v) ∧ (A -★ # v1 @{op} # v2 ⇓ inr v))%A) →
  Γ\ δ\ A ⊨ₑ {{ P1 }} e1 {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P2 }} e2 {{ Q2 }} →
  Γ\ δ\ A ⊨ₑ {{ P1 ★ P2 }} e1 @{op} e2 {{ R }}.
Proof.
  intros HQ Hax1 Hax2 Γ' Δ n ρ m [|σ] ???? Hlock He ?? HA HP;
    [typed_inversion_all|].
  assert (∃ τ1 τ2, (Γ',Δ,ρ.*2) ⊢ e1 : inr τ1 ∧
    (Γ',Δ,ρ.*2) ⊢ e2 : inr τ2 ∧ binop_typed op τ1 τ2 σ)
    as (τ1&τ2&?&?&?) by (typed_inversion_all; eauto); clear He.
  destruct HP as (m1'&m2'&?&?&?&?).
  destruct (cmap_erase_union_inv m m1' m2')
    as (m1&m2&->&?&->&->); simplify_mem_disjoint_hyps; auto.
  rewrite mem_locks_union in Hlock by auto; simpl in *; decompose_empty.
  apply (ax_expr_compose_2 Γ' δ A Q1 Q2 _ Δ (DCBinOp op) e1 e2 ρ n m1 m2
    (inr τ1) (inr τ2)); eauto using ax_expr_invariant_weaken,
    @sep_union_subseteq_l', @sep_union_subseteq_r'.
  { esolve_elem_of. }
  { esolve_elem_of. }
  clear dependent m1 m2; intros Δ' n' [|v1] [|v2] m1 m2
    ?????????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v1 v2 Γ' Δ' ρ n' (cmap_erase (m1 ∪ m2)))
    as (v'&?&HA); eauto 6 using indexes_valid_weaken.
  { rewrite cmap_erase_union.
    exists (cmap_erase m1) (cmap_erase m2); split_ands; auto.
    by rewrite <-!cmap_erase_disjoint_le. }
  destruct (HA Γ' Δ'' n'' mA) as (?&_&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  simplify_option_equality.
  assert (val_binop_ok Γ' (m1 ∪ m2 ∪ mf ∪ mA) op v1 v2).
  { eapply val_binop_ok_weaken
      with Γ' Δ' (mA ∪ cmap_erase (m1 ∪ m2)) τ1 τ2; eauto.
    intros; eapply cmap_subseteq_index_alive; eauto.
    rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality|exfalso; eauto with cstep].
  rewrite <-mem_locks_union by auto.
  apply mk_ax_next with Δ'' (m1 ∪ m2); simpl; auto.
  { constructor; auto. }
  apply ax_done; constructor; eauto using mem_lookup_typed,
    indexes_valid_weaken, assert_weaken, val_binop_typed, val_typed_weaken.
Qed.
Lemma ax_cast Γ δ A P Q1 Q2 σ e :
  (∀ v, Q1 (inr v) ⊆{Γ} (∃ v', Q2 (inr v') ∧ (A -★ cast{σ} (#v) ⇓ inr v'))%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ Q1 }} →
  Γ\ δ\ A ⊨ₑ {{ P }} cast{σ} e {{ Q2 }}.
Proof.
  intros HQ Hax Γ' Δ n ρ m [|σ'] ????? He ?? HA HP; [typed_inversion_all|].
  assert (∃ τ, (Γ',Δ,ρ.*2) ⊢ e : inr τ ∧ cast_typed τ σ ∧ ✓{Γ'} σ ∧ σ' = σ)
    as (τ&?&?&?&->) by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A Q1 _ Δ (DCCast σ) e ρ n m (inr τ)); auto.
  { esolve_elem_of. }
  clear dependent m. intros Δ' n' [a|] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  destruct (HQ v Γ' Δ' ρ n' (cmap_erase m))
    as (v'&?&HA); eauto using indexes_valid_weaken.
  destruct (HA Γ' Δ'' n'' mA) as (?&_&?); clear HA;
    eauto 4 using assert_weaken, indexes_valid_weaken.
  { rewrite <-cmap_erase_disjoint_le; auto. }
  simplify_option_equality.
  assert (val_cast_ok Γ' (m ∪ mf ∪ mA) (TType σ) v).
  { eapply val_cast_ok_weaken with Γ' Δ' (mA ∪ cmap_erase m) τ; eauto.
    intros; eapply cmap_subseteq_index_alive; eauto.
    rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  split; [solve_rcred|intros S' p _].
  inv_rcstep p; [inv_ehstep; simplify_equality|exfalso; eauto with cstep].
  apply mk_ax_next with Δ'' m; simpl; auto.
  { constructor; auto. }
  apply ax_done; constructor; eauto using mem_lookup_typed,
    indexes_valid_weaken, assert_weaken, val_cast_typed, val_typed_weaken.
Qed.
Lemma ax_expr_if Γ δ A P P' P1 P2 Q e e1 e2 :
  (∀ vb, (A ★ P' (inr (VBase vb)))%A ⊆{Γ} (@{NotOp} #VBase vb ⇓ -)%A) →
  (∀ vb, ¬base_val_is_0 vb → P' (inr (VBase vb)) ⊆{Γ} (P1 ◊)%A) →
  (∀ vb, base_val_is_0 vb → P' (inr (VBase vb)) ⊆{Γ} (P2 ◊)%A) →
  Γ\ δ\ A ⊨ₑ {{ P }} e {{ P' }} →
  Γ\ δ\ A ⊨ₑ {{ P1 }} e1 {{ Q }} → Γ\ δ\ A ⊨ₑ {{ P2 }} e2 {{ Q }} →
  Γ\ δ\ A ⊨ₑ {{ P }} if{e} e1 else e2 {{ Q }}.
Proof.
  intros HP' HP1 HP2 Hax Hax1 Hax2 Γ' Δ n ρ m τlr ????? He ????;
    simpl in *; decompose_empty.
  assert (∃ τb, (Γ',Δ,ρ.*2) ⊢ e : inr (baseT τb) ∧ τb ≠ voidT%BT ∧
    (Γ',Δ,ρ.*2) ⊢ e1 : τlr ∧ (Γ',Δ,ρ.*2) ⊢ e2 : τlr)
    as (τb&?&?&?&?) by (typed_inversion_all; eauto); clear He.
  apply (ax_expr_compose_1 Γ' δ A
    P' _ Δ (DCIf e1 e2) e ρ n m (inr (baseT τb))); auto.
  { esolve_elem_of. }
  { esolve_elem_of. }
  clear dependent m;
    intros Δ' n' [|[vb| | | |]] m ?????; typed_inversion_all.
  apply ax_further_alt.
  intros Δ'' n'' ????? Hframe; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  assert (base_val_branchable (m ∪ mf ∪ mA) vb).
  { assert (⊥ [cmap_erase m; mf; mA])
      by (rewrite <-cmap_erase_disjoint_le; auto).
    destruct (HP' vb Γ' Δ'' ρ n'' (mA ∪ cmap_erase m)) as (?&?&?&?);
      simpl; eauto using indexes_valid_weaken.
    { exists mA (cmap_erase m); split_ands;
        eauto 4 using assert_weaken, indexes_valid_weaken. }
    simplify_option_equality.
    eapply base_val_branchable_weaken with (mA ∪ cmap_erase m); eauto.
    intros; eapply cmap_subseteq_index_alive; eauto.
    rewrite (sep_commutative _ mA) by auto.
    apply sep_preserving_l; auto using
      @sep_union_subseteq_l_transitive, cmap_erase_subseteq_l. }
  split.
  { destruct (decide (base_val_is_0 vb)); solve_rcred. }
  assert (⊥ [mem_unlock_all m; mf; mA])
    by (rewrite <-mem_unlock_all_disjoint_le; auto).
  intros S' p _; inv_rcstep p; [inv_ehstep|].
  * rewrite !mem_unlock_union, <-mem_unlock_all_spec
      by (rewrite ?mem_locks_union by auto; solve_elem_of).
    apply mk_ax_next with Δ'' (mem_unlock_all m); auto.
    { constructor; auto. }
    { esolve_elem_of. }
    { eauto using mem_unlock_all_valid. }
    apply Hax1; rewrite ?mem_erase_unlock_all;
      eauto 8 using mem_unlock_all_valid, indexes_valid_weaken,
      mem_locks_unlock_all, expr_typed_weaken, funenv_valid_weaken.
    + exists mA; eauto 8 using assert_weaken, indexes_valid_weaken.
    + eapply HP1; eauto using indexes_valid_weaken, assert_weaken.
  * rewrite !mem_unlock_union, <-mem_unlock_all_spec
      by (rewrite ?mem_locks_union by auto; solve_elem_of).
    apply mk_ax_next with Δ'' (mem_unlock_all m); auto.
    { constructor; auto. }
    { esolve_elem_of. }
    { eauto using mem_unlock_all_valid. }
    apply Hax2; rewrite ?mem_erase_unlock_all;
      eauto 8 using mem_unlock_all_valid, indexes_valid_weaken,
      mem_locks_unlock_all, expr_typed_weaken, funenv_valid_weaken.
    + exists mA; eauto 8 using indexes_valid_weaken, assert_weaken.
    + eapply HP2; eauto using indexes_valid_weaken, assert_weaken.
  * destruct (decide (base_val_is_0 vb)); exfalso; eauto with cstep.
Qed.
Lemma ax_expr_comma Γ δ A P P' Q e1 e2 :
  Γ\ δ\ A ⊨ₑ {{ P }} e1 {{ λ _, P' ◊ }} →
  Γ\ δ\ A ⊨ₑ {{ P' }} e2 {{ Q }} →
  Γ\ δ\ A ⊨ₑ {{ P }} e1 ,, e2 {{ Q }}.
Proof.
  intros Hax1 Hax2 Γ' Δ n ρ m τlr2 ????? He1e2 He ???.
  assert (∃ τlr1, (Γ',Δ,ρ.*2) ⊢ e1 : τlr1 ∧ (Γ',Δ,ρ.*2) ⊢ e2 : τlr2)
    as (τlr1&?&?) by (typed_inversion_all; eauto); clear He1e2.
  simpl in He; decompose_empty.
  apply (ax_expr_compose_1 Γ' δ A
    (λ _, P' ◊)%A _ Δ (DCComma e2) e1 ρ n m τlr1); auto.
  { esolve_elem_of. }
  clear dependent m; intros Δ' n' ν m;
    rewrite assert_unlock_spec; intros ?????; simplify_equality'.
  apply ax_further; [intros; solve_rcred|].
  intros Δ'' n'' ?? S' ??? Hframe p _; inversion_clear Hframe as [mA mf|];
    simplify_equality; simplify_mem_disjoint_hyps.
  inv_rcstep p; [inv_ehstep|exfalso; eauto with cstep].
  rewrite !mem_unlock_union, <-mem_unlock_all_spec
    by (rewrite ?mem_locks_union by auto; solve_elem_of).
  assert (⊥ [mem_unlock_all m; mf; mA])
    by (rewrite <-mem_unlock_all_disjoint_le; auto).
  apply mk_ax_next with Δ'' (mem_unlock_all m); auto.
  { constructor; auto. }
  { esolve_elem_of. }
  { eauto using mem_unlock_all_valid. }
  apply Hax2; rewrite ?mem_erase_unlock_all;
    eauto 7 using mem_unlock_all_valid, indexes_valid_weaken,
    mem_locks_unlock_all, expr_typed_weaken, assert_weaken, funenv_valid_weaken.
  exists mA; eauto 8 using indexes_valid_weaken, assert_weaken.
Qed.
End axiomatic_expressions.