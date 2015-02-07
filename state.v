(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
(** The small step reduction (as defined in the file [smallstep]) is a binary
relation between execution states. In this file we define execution states, of
which we consider five variants:

- Execution of statements,
- Execution of expressions,
- Calling a function,
- Returning from a function, and,
- Undefined behavior.

The above kinds of execution states are adapted from Compcert's Cmedium. Like
CompCert, we capture undefined behavior by an explicit state for undefined
behavior. *)

(** Undefined behavior is different from the reduction semantics getting stuck.
For statically correct programs (i.e. those where all function names have a
corresponding body, labels for gotos exist, etc) the reduction semantics should
not get stuck, but might still end up in a state of undefined behavior. *)
Require Export statements memory.

(** * Definitions *)
(** Execution of statements occurs by traversal through the program context in
one of the following directions: down [↘], up [↗], to the top [⇈], or jump [↷].
When a [return e] statement is executed, and the expression [e] is evaluated to
the value [v], the direction is changed to [⇈ v]. The semantics then performs
a traversal to the top of the statement, and returns from the called function.
When a [goto l] statement is executed, the direction is changed to [↷l], and
the semantics performs a non-deterministic small step traversal through the
zipper until the label [l] is found. *)
Inductive direction (K : Set) : Set :=
  Down | Up | Top (v : val K) | Goto (l : labelname) | Throw (n : nat).
Arguments Down {_}.
Arguments Up {_}.
Arguments Top {_} _.
Arguments Goto {_} _.
Arguments Throw {_} _.

Notation "↘" := Down : C_scope.
Notation "↗" := Up : C_scope.
Notation "⇈ v" := (Top v) (at level 20) : C_scope.
Notation "↷ l" := (Goto l) (at level 20) : C_scope.
Notation "↑ n" := (Throw n) (at level 20) : C_scope.

Instance direction_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (d1 d2 : direction K) : Decision (d1 = d2).
Proof. solve_decision. Defined.

Definition direction_in {K} (d : direction K) (s : stmt K) : Prop :=
  match d with ↘ => True | ↷ l => l ∈ labels s | _ => False end.
Definition direction_out {K} (d : direction K) (s : stmt K) : Prop :=
  match d with
  | ↗ | ⇈ _ => True | ↷ l => l ∉ labels s | ↑ _ => True | _ => False
  end.
Arguments direction_in _ _ _ : simpl nomatch.
Arguments direction_out _ _ _ : simpl nomatch.
Hint Unfold direction_in direction_out.

Definition direction_in_out_dec {K} (d : direction K) s :
  { direction_in d s ∧ ¬direction_out d s } +
  { ¬direction_in d s ∧ direction_out d s }.
Proof.
 refine
  match d with
  | ↘ => left _ | ↷ l => cast_if (decide (l ∈ labels s)) | _ => right _
  end; abstract naive_solver.
Defined.
Lemma direction_in_out {K} (d : direction K) s :
  direction_in d s → direction_out d s → False.
Proof. destruct (direction_in_out_dec d s); naive_solver. Qed.

(** The data type [focus] describes the part of the program that is focused. An
execution state [state] equips a focus with a program context and memory.

- The focus [Stmt] is used for execution of statements, it contains the
  statement to be executed and the direction in which traversal should be
  performed.
- The focus [Expr] is used for expressions and contains the whole expression
  that is being executed. Notice that this constructor does not contain the set
  of locked locations due to sequenced writes, these are contained more
  structurally in the expression itself.
- The focus [Call] is used to call a function, it contains the name of the
  called function and the values of the arguments.
- The focus [Return] is used to return from the called function to the calling
  function, it contains the return value.
- The focus [Undef] is used to capture undefined behavior. It contains the
  expression that got stuck.

These focuses correspond to the five variants of execution states as described
above. *)
Inductive undef_state (K : Set) : Set :=
  | UndefExpr : ectx K → expr K → undef_state K
  | UndefBranch : esctx_item K → lockset → val K → undef_state K.
Inductive focus (K : Set) : Set :=
  | Stmt : direction K → stmt K → focus K
  | Expr : expr K → focus K
  | Call : funname → list (val K) → focus K
  | Return : funname → val K → focus K
  | Undef : undef_state K → focus K.
Record state (K : Set) : Set :=
  State { SCtx : ctx K; SFoc : focus K; SMem : mem K }.
Add Printing Constructor state.

Arguments UndefExpr {_} _ _.
Arguments UndefBranch {_} _ _ _.
Arguments Stmt {_} _ _.
Arguments Expr {_} _.
Arguments Call {_} _ _.
Arguments Return {_} _ _.
Arguments Undef {_} _.
Arguments State {_} _ _ _.
Arguments SCtx {_} _.
Arguments SFoc {_} _.
Arguments SMem {_} _.

Instance undef_state_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (S1 S2 : undef_state K) : Decision (S1 = S2).
Proof. solve_decision. Defined.
Instance focus_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (φ1 φ2 : focus K) : Decision (φ1 = φ2).
Proof. solve_decision. Defined.
Instance state_eq_dec {K : Set} `{Env K}
  (S1 S2 : state K) : Decision (S1 = S2).
Proof. solve_decision. Defined.
Instance focus_locks {K} : Locks (focus K) := λ φ,
  match φ with Stmt _ s => locks s | Expr e => locks e | _ => ∅ end.

Definition initial_state {K} (m : mem K)
  (f : funname) (vs : list (val K)) : state K := State [] (Call f vs) m.
Inductive is_final_state {K} (v : val K) : state K → Prop :=
  | Return_final f m : is_final_state v (State [] (Return f v) m).
Inductive is_undef_state {K} : state K → Prop :=
  | Undef_undef k Su m : is_undef_state (State k (Undef Su) m).

Instance is_final_state_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (v : val K) S : Decision (is_final_state v S).
Proof.
 refine
  match S with
  | State [] (Return _ v') _ => cast_if (decide (v = v'))
  | _ => right _
  end; abstract first [subst; constructor|by inversion 1].
Defined.
Instance is_undef_state_dec {K} (S : state K) : Decision (is_undef_state S).
Proof.
 refine match S with State _ (Undef _) _ => left _ | _ => right _ end;
    abstract first [constructor|by inversion 1].
Defined.
 
