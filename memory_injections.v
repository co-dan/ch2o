(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export references memory_basics.

Inductive meminj (Ti : Set) :=
  | meminj_id : meminj Ti
  | meminj_map : indexmap (index * ref Ti) → meminj Ti.
Arguments meminj_id {_}.
Arguments meminj_map {_} _.
Instance meminj_dec {Ti : Set} `{∀ τi1 τi2 : Ti, Decision (τi1 = τi2)}
  (f g : meminj Ti) : Decision (f = g).
Proof. solve_decision. Defined.
Instance meminj_lookup {Ti} : Lookup index (index * ref Ti) (meminj Ti) :=
  λ o f, match f with meminj_id => Some (o, []) | meminj_map m => m !! o end.
Definition meminj_compose {Ti} (f g : meminj Ti) : meminj Ti :=
  match f, g with
  | meminj_id, meminj_id => meminj_id
  | meminj_map m, meminj_id => meminj_map m
  | meminj_id, meminj_map m => meminj_map m
  | meminj_map m1, meminj_map m2 => meminj_map $
     merge (λ yr _ : option (index * ref Ti),
       '(y1,r1) ← yr; '(y2,r2) ← m1 !! y1; Some (y2, r1 ++ r2)) m2 ∅
  end.
Arguments meminj_compose _ !_ !_ /.
Infix "◎" := meminj_compose (at level 40, left associativity) : C_scope.
Notation "(◎)" := meminj_compose (only parsing) : C_scope.

Definition meminj_injective {Ti} (f : meminj Ti) : Prop := ∀ o1 o2 o r1 r2,
  f !! o1 = Some (o,r1) → f !! o2 = Some (o,r2) → o1 = o2 ∨ r1 ⊥ r2.
Instance meminj_subseteq {Ti} : SubsetEq (meminj Ti) := λ f1 f2,
  ∀ o o' r', f1 !! o = Some (o',r') → f2 !! o = Some (o',r').

Section meminj.
Context {Ti : Set}.
Implicit Types f g : meminj Ti.
Implicit Types o : index.
Implicit Types r : ref Ti.

Lemma meminj_eq f g : (∀ o, f !! o = g !! o) → f = g.
Proof.
  intros Hfg. destruct f as [|m1], g as [|m2].
  * done.
  * generalize (Hfg (fresh (dom _ m2))); unfold lookup; simpl.
    by rewrite (proj1 (not_elem_of_dom _ _)) by (apply is_fresh).
  * generalize (Hfg (fresh (dom _ m1))); unfold lookup; simpl.
    by rewrite (proj1 (not_elem_of_dom _ _)) by (apply is_fresh).
  * f_equal. apply map_eq, Hfg.
Qed.

Lemma lookup_meminj_id o : @meminj_id Ti !! o = Some (o, []).
Proof. done. Qed.
Lemma lookup_meminj_id_Some o1 o2 r :
  meminj_id !! o1 = Some (o2,r) ↔ o2 = o1 ∧ r = [].
Proof. rewrite lookup_meminj_id; naive_solver. Qed.
Lemma lookup_meminj_compose f g o :
  (f ◎ g) !! o = '(y1,r1) ← g !! o; '(y2,r2) ← f !! y1; Some (y2,r1 ++ r2).
Proof.
  unfold lookup; destruct f as [|m1], g as [|m2]; csimpl.
  * done.
  * by destruct (_ !! o) as [[??]|]; csimpl; rewrite ?(right_id_L [] (++)).
  * by destruct (_ !! o) as [[??]|].
  * by rewrite lookup_merge by done.
Qed.
Lemma lookup_meminj_compose_Some f g o1 o3 r :
  (f ◎ g) !! o1 = Some (o3,r) ↔
  ∃ o2 r2 r3, g !! o1 = Some (o2,r2) ∧ f !! o2 = Some (o3,r3) ∧ r = r2 ++ r3.
Proof.
  rewrite lookup_meminj_compose. split.
  * intros. destruct (g !! o1) as [[o2 r2]|] eqn:?; simplify_equality'.
    destruct (f !! o2) as [[??]|] eqn:?; naive_solver.
  * by intros (?&?&?&?&?&?); simplify_option_equality.
Qed.

Global Instance: LeftId (@eq (meminj Ti)) meminj_id (◎).
Proof. by intros []. Qed.
Global Instance: RightId (@eq (meminj Ti)) meminj_id (◎).
Proof. by intros []. Qed.
Global Instance: Associative (@eq (meminj Ti)) (◎).
Proof.
  intros f g h. apply meminj_eq. intros o1. rewrite !lookup_meminj_compose.
  destruct (h !! o1) as [[o2 r2]|]; csimpl; [|done].
  rewrite !lookup_meminj_compose.
  destruct (g !! o2) as [[o3 r3]|]; csimpl; [|done].
  by destruct (f !! o3) as [[??]|]; csimpl; rewrite ?(associative_L (++)).
Qed.
Lemma meminj_positive_l f g : f ◎ g = meminj_id → f = meminj_id.
Proof. by destruct f, g. Qed.
Lemma meminj_positive_r f g : f ◎ g = meminj_id → g = meminj_id.
Proof. by destruct f, g. Qed.

Lemma meminj_id_injective : meminj_injective (@meminj_id Ti).
Proof. intros x1 x2 y r1 r2; rewrite !lookup_meminj_id; naive_solver. Qed.
Lemma meminj_compose_injective f g :
  meminj_injective f → meminj_injective g → meminj_injective (f ◎ g).
Proof.
  intros Hf Hg o1 o2 o r1 r2; rewrite !lookup_meminj_compose_Some.
  intros (o1'&r1'&r1''&?&?&->) (o2'&r2'&r2''&?&?&->).
  destruct (decide (o1 = o2)); [by left|].
  destruct (Hf o1' o2' o r1'' r2'') as [->|?]; simplify_equality'; auto.
  { destruct (Hg o1 o2 o2' r1' r2') as [->|?]; auto.
    right. by apply ref_disjoint_here_app_1. }
  right. by apply ref_disjoint_app_l, ref_disjoint_app_r.
Qed.
Lemma meminj_injective_alt f o1 o2 o r1 r2 :
  meminj_injective f → f !! o1 = Some (o,r1) → f !! o2 = Some (o,r2) →
  o1 = o2 ∨ o1 ≠ o2 ∧ r1 ⊥ r2.
Proof.
  intros Hf ??. destruct (decide (o1 = o2)); [by left|].
  destruct (Hf o1 o2 o r1 r2); auto.
Qed.
Lemma meminj_injective_ne f o1 o2 o3 o4 r2 r4 :
  meminj_injective f → f !! o1 = Some (o2,r2) → f !! o3 = Some (o4,r4) →
  o1 ≠ o3 → o2 ≠ o4 ∨ o2 = o4 ∧ r2 ⊥ r4.
Proof.
  intros Hf ???. destruct (decide (o2 = o4)) as [->|]; auto.
  destruct (Hf o1 o3 o4 r2 r4); auto.
Qed.
Global Instance: PartialOrder ((⊆) : relation (meminj Ti)).
Proof.
  repeat split.
  * by intros f o o' r'.
  * intros f1 f2 f3. unfold subseteq, meminj_subseteq. naive_solver.
  * intros f1 f2; unfold subseteq, meminj_subseteq; intros.
    apply meminj_eq. intros o. apply option_eq. intros [o' r']; naive_solver.
Qed.
End meminj.

