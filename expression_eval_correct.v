(* Copyright (c) 2012-2013, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
(** We prove some correspondence results between the denotation semantics for
pure expressions and the small step operational semantics. *)
Require Export smallstep expression_eval.

Lemma ehstep_expr_eval_inv δ ρ m v e1 m1 e2 m2 :
  ρ ⊢ₕ e1, m1 ⇒ e2, m2 →
  ⟦ e1 ⟧ δ ρ m = Some v →
  m ⊆ m1 →
  m2 = m1 ∧ ⟦ e2 ⟧ δ ρ m = Some v.
Proof.
  by destruct 1; intros; try solve [simplify_expr_equality;
    rewrite ?mem_unlock_empty_locks; eauto].
Qed.

Lemma ehstep_expr_eval δ ρ e1 m v :
  ⟦ e1 ⟧ δ ρ m = Some v →
  is_redex e1 →
  (∃ e2, ρ ⊢ₕ e1, m ⇒ e2, m ∧ ⟦ e2 ⟧ δ ρ m = Some v) ∨
  (∃ f F Ωs vs,
    e1 = (call f @ zip_with EVal Ωs vs)%E ∧
    same_length Ωs vs ∧
    δ !! f = Some F ∧
    F vs = Some v).
Proof.
  destruct 2; intros;
    repeat match goal with
    | H : is_value _ |- _ => inversion H; subst; clear H
    | H : Forall is_value _ |- _ =>
      apply Forall_is_value_alt in H; destruct H as (?&?&?&?)
    | H : Forall2 (λ e v, ⟦ e ⟧ _ _ _ = Some v) _ _ |- _ =>
      apply Forall2_expr_eval_val_inv in H; [| done]
    | _ => progress simplify_expr_equality
    end; try naive_solver (eauto; do_ehstep).
Qed.

Lemma ehstep_expr_eval_subst δ ρ m (E : ectx) e1 v :
  ⟦ subst E e1 ⟧ δ ρ m = Some v →
  is_redex e1 →
  (∃ e2, ρ ⊢ₕ e1, m ⇒ e2, m ∧ ⟦ subst E e2 ⟧ δ ρ m = Some v) ∨
  (∃ f F Ωs vs w,
    e1 = (call f @ zip_with EVal Ωs vs)%E ∧
    same_length Ωs vs ∧
    δ !! f = Some F ∧
    F vs = Some w ∧
    ⟦ subst E (val w)%E ⟧ δ ρ m = Some v).
Proof.
  intros Heval ?.
  destruct (expr_eval_subst_inv _ _ _ _ _ _ Heval) as [v' [Heval' ?]].
  destruct (ehstep_expr_eval _ _ _ _ _ Heval')
    as [(e2&?&?)|(f&F&Ωs&vs&?&?&?&?)]; trivial.
  * left. exists e2. split; [done |].
    rewrite (subst_preserves_expr_eval _ _ _ _ _ e1); congruence.
  * right. exists f F Ωs vs. exists v'. eauto.
Qed.

Lemma ehsafe_expr_eval_subst δ ρ m (E : ectx) e v :
  ⟦ subst E e ⟧ δ ρ m = Some v →
  is_redex e →
  ρ ⊢ₕ safe e, m.
Proof.
  intros Heval ?.
  destruct (ehstep_expr_eval_subst _ _ _ _ _ _ Heval)
    as [(e2&?&?)|(f&F&vs&?&?&?&?&?)]; trivial; subst.
  * eauto using ehsafe_step.
  * by constructor.
Qed.

Lemma cred_expr_eval δp δ e k m v :
  ⟦ e ⟧ δp (get_stack k) m = Some v →
  ¬is_value e →
  red (cstep_in_ctx δ k) (State k (Expr e) m).
Proof.
  intros Heval He.
  destruct (is_value_is_redex _ He) as [E' [e' [??]]]; subst.
  destruct (expr_eval_subst_inv _ _ _ _ _ _ Heval) as [v' [??]].
  destruct (ehstep_expr_eval_subst _ _ _ _ _ _ Heval)
    as [(e2&?&?)|(f&F&vs&?&?&?&?&?)]; trivial; subst; solve_cred.
Qed.