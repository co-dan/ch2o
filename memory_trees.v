(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export permission_bits ctrees.
Local Open Scope ctype_scope.

Notation mtree K := (ctree K (pbit K)).

Section operations.
  Context `{Env K}.

  Global Instance type_of_ctree : TypeOf (type K) (mtree K) := λ w,
    match w with
    | MBase τb _ => baseT τb
    | MArray τ ws => τ.[length ws]
    | MStruct s _ => structT s
    | MUnion s _ _ _ | MUnionAll s _ => unionT s
    end.
  Inductive ctree_typed' (Γ : env K) (Δ : memenv K) :
       mtree K → type K → Prop :=
    | MBase_typed τb xbs :
       ✓{Γ} τb → ✓{Γ,Δ}* xbs → length xbs = bit_size_of Γ (baseT τb) →
       ctree_typed' Γ Δ (MBase τb xbs) (baseT τb)
    | MArray_typed τ n ws :
       n = length ws → Forall (λ w, ctree_typed' Γ Δ w τ) ws → n ≠ 0 →
       ctree_typed' Γ Δ (MArray τ ws) (τ.[n])
    | MStruct_typed s wxbss τs :
       Γ !! s = Some τs → Forall2 (ctree_typed' Γ Δ ∘ fst) wxbss τs →
       ✓{Γ,Δ}2** wxbss →
       Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss →
       length ∘ snd <$> wxbss = field_bit_padding Γ τs →
       ctree_typed' Γ Δ (MStruct s wxbss) (structT s)
    | MUnion_typed s i τs w xbs τ :
       Γ !! s = Some τs → τs !! i = Some τ → ctree_typed' Γ Δ w τ →
       ✓{Γ,Δ}* xbs → pbit_indetify <$> xbs = xbs →
       bit_size_of Γ (unionT s) = bit_size_of Γ τ + length xbs →
       ¬(ctree_unmapped w ∧ Forall sep_unmapped xbs) →
       ctree_typed' Γ Δ (MUnion s i w xbs) (unionT s)
    | MUnionAll_typed s τs xbs :
       Γ !! s = Some τs → ✓{Γ,Δ}* xbs → length xbs = bit_size_of Γ (unionT s) →
       ctree_typed' Γ Δ (MUnionAll s xbs) (unionT s).
  Global Instance ctree_typed:
    Typed (env K * memenv K) (type K) (mtree K) := curry ctree_typed'.

  Lemma ctree_typed_inv_l Γ Δ (P : type K → Prop) w τ :
    (Γ,Δ) ⊢ w : τ →
    match w with
    | MBase τb xbs =>
       (✓{Γ} τb → length xbs = bit_size_of Γ (baseT τb) →
         ✓{Γ,Δ}* xbs → P (baseT τb)) → P τ
    | MArray τ' ws =>
       ((Γ,Δ) ⊢* ws : τ' → length ws ≠ 0 → P (τ'.[length ws])) → P τ
    | MStruct s wxbss =>
       (∀ τs, Γ !! s = Some τs → (Γ,Δ) ⊢1* wxbss :* τs → ✓{Γ,Δ}2** wxbss →
         Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss →
         length ∘ snd <$> wxbss = field_bit_padding Γ τs → P (structT s)) → P τ
    | MUnion s i w xbs =>
       (∀ τs τ, Γ !! s = Some τs → τs !! i = Some τ → (Γ,Δ) ⊢ w : τ →
         ✓{Γ,Δ}* xbs → pbit_indetify <$> xbs = xbs →
         bit_size_of Γ (unionT s) = bit_size_of Γ τ + length xbs →
         ¬(ctree_unmapped w ∧ Forall sep_unmapped xbs) → P (unionT s)) → P τ
    | MUnionAll s xbs =>
       (∀ τs, Γ !! s = Some τs → ✓{Γ,Δ}* xbs →
         length xbs = bit_size_of Γ (unionT s) → P (unionT s)) → P τ
    end.
  Proof. destruct 1; simplify_equality'; eauto. Qed.
  Lemma ctree_typed_inv_r Γ Δ (P : mtree K → Prop) w τ :
    (Γ,Δ) ⊢ w : τ →
    match τ with
    | baseT τb =>
       (∀ xbs, ✓{Γ} τb → length xbs = bit_size_of Γ (baseT τb) →
         ✓{Γ,Δ}* xbs → P (MBase τb xbs)) → P w
    | τ.[n] =>
       (∀ ws, n = length ws → (Γ,Δ) ⊢* ws : τ → n ≠ 0 → P (MArray τ ws)) → P w
    | structT s =>
       (∀ wxbss τs, Γ !! s = Some τs → (Γ,Δ) ⊢1* wxbss :* τs →
         ✓{Γ,Δ}2** wxbss →
         Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss →
         length ∘ snd <$> wxbss = field_bit_padding Γ τs →
         P (MStruct s wxbss)) → P w
    | unionT s =>
       (∀ i τs w xbs τ, Γ !! s = Some τs → τs !! i = Some τ → (Γ,Δ) ⊢ w : τ →
         ✓{Γ,Δ}* xbs → pbit_indetify <$> xbs = xbs →
         bit_size_of Γ (unionT s) = bit_size_of Γ τ + length xbs →
         ¬(ctree_unmapped w ∧ Forall sep_unmapped xbs) →
         P (MUnion s i w xbs)) →
       (∀ τs xbs, Γ !! s = Some τs → ✓{Γ,Δ}* xbs →
         length xbs = bit_size_of Γ (unionT s) → P (MUnionAll s xbs)) →
       P w
    end.
  Proof. destruct 1; eauto. Qed.
  Lemma ctree_typed_inv Γ Δ (P : Prop) w τ :
    (Γ,Δ) ⊢ w : τ →
    match w, τ with
    | MBase τb xbs, baseT τb' =>
       (τb' = τb → ✓{Γ} τb → length xbs = bit_size_of Γ (baseT τb) →
         ✓{Γ,Δ}* xbs → P) → P
    | MArray τ' ws, τ''.[n] =>
       (τ'' = τ' → n = length ws → (Γ,Δ) ⊢* ws : τ' → length ws ≠ 0 → P) → P
    | MStruct s wxbss, structT s' =>
       (∀ τs, s' = s → Γ !! s = Some τs → (Γ,Δ) ⊢1* wxbss :* τs →
         ✓{Γ,Δ}2** wxbss →
         Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss →
         length ∘ snd <$> wxbss = field_bit_padding Γ τs → P) → P
    | MUnion s i w xbs, unionT s' =>
       (∀ τs τ, s' = s → Γ !! s = Some τs → τs !! i = Some τ → (Γ,Δ) ⊢ w : τ →
         ✓{Γ,Δ}* xbs → pbit_indetify <$> xbs = xbs →
         bit_size_of Γ (unionT s) = bit_size_of Γ τ + length xbs →
         ¬(ctree_unmapped w ∧ Forall sep_unmapped xbs) → P) → P
    | MUnionAll s xbs, unionT s' =>
       (∀ τs, s' = s → Γ !! s = Some τs → ✓{Γ,Δ}* xbs →
         length xbs = bit_size_of Γ (unionT s) → P) → P
    | _, _ => P
    end.
  Proof. destruct 1; simplify_equality'; eauto. Qed.
  Section ctree_typed_ind.
    Context (Γ : env K) (Δ : memenv K) (P : mtree K → type K → Prop).
    Context (Pbase : ∀ τb xbs,
      ✓{Γ} τb → ✓{Γ,Δ}* xbs →
      length xbs = bit_size_of Γ (baseT τb) → P (MBase τb xbs) (baseT τb)).
    Context (Parray : ∀ ws τ,
      (Γ,Δ) ⊢* ws : τ → Forall (λ w, P w τ) ws →
      length ws ≠ 0 → P (MArray τ ws) (τ.[length ws])).
    Context (Pstruct : ∀ s wxbss τs,
      Γ !! s = Some τs → (Γ,Δ) ⊢1* wxbss :* τs → Forall2 (P ∘ fst) wxbss τs →
      ✓{Γ,Δ}2** wxbss →
      Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss →
      length ∘ snd <$> wxbss = field_bit_padding Γ τs →
      P (MStruct s wxbss) (structT s)).
    Context (Punion : ∀ s i τs w xbs τ,
      Γ !! s = Some τs → τs !! i = Some τ → (Γ,Δ) ⊢ w : τ → P w τ →
      ✓{Γ,Δ}* xbs → pbit_indetify <$> xbs = xbs →
      bit_size_of Γ (unionT s) = bit_size_of Γ τ + length xbs →
      ¬(ctree_unmapped w ∧ Forall sep_unmapped xbs) →
      P (MUnion s i w xbs) (unionT s)).
    Context (Punion_all : ∀ s τs xbs,
      Γ !! s = Some τs → ✓{Γ,Δ}* xbs → length xbs = bit_size_of Γ (unionT s) →
      P (MUnionAll s xbs) (unionT s)).
    Definition ctree_typed_ind : ∀ w τ, ctree_typed' Γ Δ w τ → P w τ.
    Proof.
      fix 3; destruct 1; simplify_equality';
        eauto using Forall2_impl, Forall_impl.
    Qed.
  End ctree_typed_ind.

  Global Instance mtree_check :
      TypeCheck (env K * memenv K) (type K) (mtree K) :=
    fix go ΓΔ w {struct w} := let _ : TypeCheck _ _ _ := @go in
    match w with
    | MBase τb xbs =>
       guard (✓{ΓΔ.1} τb);
       guard (✓{ΓΔ}* xbs);
       guard (length xbs = bit_size_of (ΓΔ.1) (baseT τb));
       Some (baseT τb)
    | MArray τ ws =>
       τs ← mapM (type_check ΓΔ) ws;
       guard (length ws ≠ 0);
       guard (Forall (τ =) τs);
       Some (τ.[length ws])
    | MStruct s wxbss =>
       τs ← ΓΔ.1 !! s;
       τs' ← mapM (type_check ΓΔ ∘ fst) wxbss;
       guard (τs' = τs);
       guard (✓{ΓΔ}2** wxbss);
       guard (Forall (λ wxbs, pbit_indetify <$> wxbs.2 = wxbs.2) wxbss);
       guard (length ∘ snd <$> wxbss = field_bit_padding (ΓΔ.1) τs);
       Some (structT s)
    | MUnion s i w xbs =>
       τ ← ΓΔ.1 !! s ≫= (!! i);
       τ' ← type_check ΓΔ w;
       guard (τ' = τ);
       guard (✓{ΓΔ}* xbs);
       guard (pbit_indetify <$> xbs = xbs);
       guard (bit_size_of (ΓΔ.1) (unionT s)
         = bit_size_of (ΓΔ.1) τ + length xbs);
       guard (¬(ctree_unmapped w ∧ Forall sep_unmapped xbs));
       Some (unionT s)
    | MUnionAll s xbs =>
       τs ← ΓΔ.1 !! s;
       guard (✓{ΓΔ}* xbs);
       guard (length xbs = bit_size_of (ΓΔ.1) (unionT s));
       Some (unionT s)
    end.

  Inductive union_free : mtree K → Prop :=
    | MBase_union_free τb xbs : union_free (MBase τb xbs)
    | MArray_union_free τ ws : Forall union_free ws → union_free (MArray τ ws)
    | MStruct_union_free s wxbss :
       Forall (union_free ∘ fst) wxbss → union_free (MStruct s wxbss)
    | MUnionAll_union_free s xbs : union_free (MUnionAll s xbs).
  Definition union_reset : mtree K → mtree K :=
    fix go w :=
    match w with
    | MBase τb xbs => MBase τb xbs
    | MArray τ ws => MArray τ (go <$> ws)
    | MStruct s wxbss => MStruct s (prod_map go id <$> wxbss)
    | MUnion s i w xbs => MUnionAll s (ctree_flatten w ++ xbs)
    | MUnionAll s xbs => MUnionAll s xbs
    end.
  Section union_free_ind.
    Context (P : mtree K → Prop).
    Context (Pbase : ∀ τ xbs, P (MBase τ xbs)).
    Context (Parray : ∀ τ ws,
      Forall union_free ws → Forall P ws → P (MArray τ ws)).
    Context (Pstruct : ∀ s wxbss,
      Forall (union_free ∘ fst) wxbss → Forall (P ∘ fst) wxbss →
      P (MStruct s wxbss)).
    Context (Punion_bits : ∀ s xbs, P (MUnionAll s xbs)).
    Definition union_free_ind_alt: ∀ w, union_free w → P w.
    Proof. fix 2; destruct 1; eauto using Forall_impl. Qed.
  End union_free_ind.
  Global Instance union_free_dec: ∀ w : mtree K, Decision (union_free w).
  Proof.
   refine (
    fix go w :=
    match w return Decision (union_free w) with
    | MBase _ _ => left _
    | MArray _ ws => cast_if (decide (Forall union_free ws))
    | MStruct _ wxbss => cast_if (decide (Forall (union_free ∘ fst) wxbss))
    | MUnion _ _ _ _ => right _
    | MUnionAll _ _ => left _
    end); clear go; abstract first [by constructor | by inversion 1].
  Defined.

  Definition array_unflatten {A B} (Γ : env K) (f : list A → B)
      (τ : type K) : nat → list A → list B :=
    let sz := bit_size_of Γ τ in fix go n bs :=
    match n with 0 => [] | S n => f (take sz bs) :: go n (drop sz bs) end.
  Definition struct_unflatten_aux {A B}
      (f : type K → list A → B) : list (nat * type K) → list A → list B :=
    fix go τs bs :=
    match τs with
    | [] => [] | (sz,τ) :: τs => f τ (take sz bs) :: go τs (drop sz bs)
    end.
  Definition struct_unflatten {A B} (Γ : env K)
      (f : type K → list A → B) (τs : list (type K)) : list A → list B :=
    struct_unflatten_aux f (zip (field_bit_sizes Γ τs) τs).
  Definition ctree_unflatten (Γ : env K) :
      type K → list (pbit K) → mtree K := type_iter
    (**i TBase =>     *) (λ τb xbs, MBase τb xbs)
    (**i TArray =>    *) (λ τ n go xbs, MArray τ (array_unflatten Γ go τ n xbs))
    (**i TCompound => *) (λ c s τs go xbs,
      match c with
      | Struct_kind =>
         MStruct s (struct_unflatten Γ (λ τ xbs,
           let τsz := bit_size_of Γ τ
           in (go τ (take τsz xbs), pbit_indetify <$> drop τsz xbs)
         ) τs xbs)
      | Union_kind => MUnionAll s xbs
      end) Γ.

  Definition ctree_new (Γ : env K) (xb : pbit K) (τ : type K) : mtree K :=
    ctree_unflatten Γ τ (replicate (bit_size_of Γ τ) xb).

  Global Instance ctree_lookup_seg:
      LookupE (env K) (ref_seg K) (mtree K) (mtree K) := λ Γ rs w,
    match rs, w with
    | RArray i τ n, MArray τ' ws =>
       guard (n = length ws); guard (τ = τ'); ws !! i
    | RStruct i s, MStruct s' wxbss => guard (s = s'); fst <$> wxbss !! i
    | RUnion i s β, MUnion s' j w xbs =>
       guard (s = s');
       if decide (i = j) then Some w else
       guard (β = false);
       τ ← Γ !! s ≫= (!! i);
       guard (ctree_unshared w);
       guard (Forall sep_unshared xbs);
       let xbs' := ctree_flatten w ++ xbs in
       Some (ctree_unflatten Γ τ (take (bit_size_of Γ τ) xbs'))
    | RUnion i s _, MUnionAll s' xbs =>
       guard (s = s'); 
       τ ← Γ !! s ≫= (!! i);
       guard (Forall sep_unshared xbs);
       Some (ctree_unflatten Γ τ (take (bit_size_of Γ τ) xbs))
    | _, _ => None
    end.
  Global Instance ctree_lookup:
      LookupE (env K) (ref K) (mtree K) (mtree K) :=
    fix go Γ r w := let _ : LookupE _ _ _ _ := @go in
    match r with [] => Some w | rs :: r => w !!{Γ} r ≫= lookupE Γ rs end.

  Definition ctree_alter_seg (Γ : env K) (g : mtree K → mtree K)
      (rs : ref_seg K) (w : mtree K) : mtree K :=
    match rs, w with
    | RArray i _ _, MArray τ ws => MArray τ (alter g i ws)
    | RStruct i _, MStruct s wxbss => MStruct s (alter (prod_map g id) i wxbss)
    | RUnion i _ _, MUnion s j w' xbs' =>
       if decide (i = j) then MUnion s i (g w') xbs'
       else default w (Γ !! s ≫= (!! i)) $ λ τ,
         let xbs := ctree_flatten w' ++ xbs' in
         MUnion s i (g (ctree_unflatten Γ τ (take (bit_size_of Γ τ) xbs)))
                    (pbit_indetify <$> drop (bit_size_of Γ τ) xbs)
    | RUnion i _ _, MUnionAll s xbs => default w (Γ !! s ≫= (!! i)) $ λ τ,
       MUnion s i (g (ctree_unflatten Γ τ (take (bit_size_of Γ τ) xbs)))
                  (pbit_indetify <$> drop (bit_size_of Γ τ) xbs)
    | _, _ => w
    end.
  Fixpoint ctree_alter (Γ : env K) (g : mtree K → mtree K)
      (r : ref K) : mtree K → mtree K :=
    match r with
    | [] => g | rs :: r => ctree_alter Γ (ctree_alter_seg Γ g rs) r
    end.

  Global Instance ctree_lookup_byte:
      LookupE (env K) nat (mtree K) (mtree K) :=
    λ Γ i w, ctree_unflatten Γ ucharT <$>
      sublist_lookup (i * char_bits) char_bits (ctree_flatten w).
  Definition ctree_alter_byte (Γ : env K) (f : mtree K → mtree K)
      (i : nat) (w : mtree K) : mtree K :=
    ctree_unflatten Γ (type_of w) $
      sublist_alter (ctree_flatten ∘ f ∘ ctree_unflatten Γ ucharT)
                    (i * char_bits) char_bits (ctree_flatten w).

  Definition ctree_singleton_seg (Γ : env K)
    (rs : ref_seg K) (w : mtree K) : mtree K :=
    match rs with
    | RArray i τ n => MArray τ (<[i:=w]>(replicate n (ctree_new Γ ∅ τ)))
    | RStruct i s =>
       default w (Γ !! s) $ λ τs,
       MStruct s (zip (<[i:=w]>(ctree_new Γ ∅ <$> τs))
         (flip replicate ∅ <$> field_bit_padding Γ τs))
    | RUnion i s _ =>
       default w (Γ !! s ≫= (!!i)) $ λ τ,
       let sz := bit_size_of Γ (unionT s) - bit_size_of Γ τ in
       MUnion s i w (replicate sz ∅)
    end.
  Fixpoint ctree_singleton (Γ : env K)
      (r : ref K) (w : mtree K) : mtree K :=
    match r with
    | [] => w
    | rs :: r => ctree_singleton Γ r (ctree_singleton_seg Γ rs w)
    end.
End operations.

Section memory_trees.
Context `{EnvSpec K}.
Implicit Types Γ : env K.
Implicit Types α : bool.
Implicit Types Δ : memenv K.
Implicit Types τb : base_type K.
Implicit Types τ σ : type K.
Implicit Types τs σs : list (type K).
Implicit Types o : index.
Implicit Types xb : pbit K.
Implicit Types xbs : list (pbit K).
Implicit Types w : mtree K.
Implicit Types ws : list (mtree K).
Implicit Types wxbs : mtree K * list (pbit K).
Implicit Types wxbss : list (mtree K * list (pbit K)).
Implicit Types rs : ref_seg K.
Implicit Types r : ref K.
Implicit Types g : mtree K → mtree K.

Hint Resolve Forall_take Forall_drop Forall_app_2 Forall_replicate.
Hint Resolve Forall2_take Forall2_drop Forall2_app.
Hint Immediate env_valid_lookup env_valid_lookup_lookup.
Hint Extern 0 (Separation _) => apply (_ : Separation (pbit K)).
Hint Immediate TArray_valid_inv_type pbit_empty_valid.

(** ** General properties of the typing judgment *)
Lemma ctree_typed_type_valid Γ Δ w τ : (Γ,Δ) ⊢ w : τ → ✓{Γ} τ.
Proof.
  induction 1 using @ctree_typed_ind; econstructor; decompose_Forall_hyps;
    try match goal with
    | H : length ?ws ≠ 0, H2 : Forall _ ?ws |- _ => destruct H2; [done|]
    end; eauto.
Qed.
Hint Immediate ctree_typed_type_valid.
Global Instance: TypeOfSpec (env K * memenv K) (type K) (mtree K).
Proof.
  intros [Γ Δ]. induction 1 using @ctree_typed_ind; decompose_Forall_hyps;
    try match goal with
    | H : length ?ws ≠ 0, H2 : Forall _ ?ws |- _ => destruct H2; [done|]
    end; simpl; eauto with f_equal.
Qed.
Local Arguments type_check _ _ _ _ _ !_ /.
Global Instance:
  TypeCheckSpec (env K * memenv K) (type K) (mtree K) (λ _, True).
Proof.
  intros [Γ Δ]. assert (∀ ws τs,
    Forall (λ w, ∀ τ, type_check (Γ,Δ) w = Some τ → (Γ,Δ) ⊢ w : τ) ws →
    Forall2 (λ w τ, type_check (Γ,Δ) w = Some τ) ws τs →
    (Γ,Δ) ⊢* ws :* τs) by (intros; decompose_Forall; eauto).
  assert (∀ ws τ,
    (Γ,Δ) ⊢* ws : τ → Forall (λ w, type_check (Γ,Δ) w = Some τ) ws →
    mapM (type_check (Γ,Δ)) ws = Some (replicate (length ws) τ)).
  { intros. apply mapM_Some,Forall2_replicate_r; decompose_Forall_hyps; eauto. }
  intros w τ _. split.
  * revert τ. induction w using @ctree_ind_alt; intros;
      repeat (progress simplify_option_equality || case_match);
      repeat match goal with
      | H : mapM _ _ = Some _ |- _ => apply mapM_Some_1 in H
      end; typed_constructor;
      eauto using Forall2_Forall_typed; decompose_Forall; subst; eauto.
  * by induction 1 using @ctree_typed_ind;
      repeat (simplify_option_equality || case_match
        || decompose_Forall_hyps || erewrite ?mapM_Some_2 by eauto);
      repeat match goal with
      | H : ¬Forall _ (replicate _ _) |- _ =>
        by destruct H; apply Forall_replicate_eq
      end.
Qed.
Lemma ctree_typed_weaken Γ1 Γ2 Δ1 Δ2 w τ :
  ✓ Γ1 → (Γ1,Δ1) ⊢ w : τ → Γ1 ⊆ Γ2 → Δ1 ⇒ₘ Δ2 → (Γ2,Δ2) ⊢ w : τ.
Proof.
  intros ? Hw ??. induction Hw using @ctree_typed_ind; typed_constructor;
    eauto using base_type_valid_weaken,
      lookup_compound_weaken, Forall_impl, pbit_valid_weaken;
    by erewrite <-?(bit_size_of_weaken Γ1 Γ2),
      <-?(field_bit_padding_weaken Γ1 Γ2)
      by eauto using TBase_valid, TCompound_valid.
Qed.
Lemma ctree_typed_sep_valid Γ Δ w τ : (Γ,Δ) ⊢ w : τ → ctree_valid w.
Proof.
  induction 1 using @ctree_typed_ind; constructor; eauto using Forall_impl,
    Forall2_Forall_l, Forall_true, pbit_valid_sep_valid.
Qed.

(** ** Properties of the [ctree_flatten] function *)
Lemma ctree_flatten_length Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → length (ctree_flatten w) = bit_size_of Γ τ.
Proof.
  intros HΓ. revert w τ. refine (ctree_typed_ind _ _ _ _ _ _ _ _); simpl.
  * done.
  * intros ws τ _ IH _; simpl. rewrite bit_size_of_array.
    induction IH; csimpl; rewrite ?app_length; f_equal; auto.
  * intros s wxbss τs Hs _ IH _ _ Hxbss; erewrite bit_size_of_struct by eauto.
    clear Hs. revert wxbss Hxbss IH. unfold field_bit_padding.
    induction (bit_size_of_fields _ τs HΓ); intros [|??] ??;
      decompose_Forall_hyps; rewrite ?app_length; f_equal; auto with lia.
  * intros s i τs w xbs τ ?? _ <- _ _ ? _. by rewrite app_length.
  * done.
Qed.
Lemma ctree_flatten_valid Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ✓{Γ,Δ}* (ctree_flatten w).
Proof.
  intros HΓ. revert w τ.
  refine (ctree_typed_ind _ _ _ _ _ _ _ _); simpl; auto 2.
  * intros ws τ _ IH _. induction IH; decompose_Forall_hyps; auto.
  * intros s wxbss τs _ _ IH ? _ _. induction IH; decompose_Forall_hyps; auto.
Qed.
Lemma ctree_flatten_union_reset w :
  ctree_flatten (union_reset w) = ctree_flatten w.
Proof.
  induction w as [| |s wxbss IH| |] using @ctree_ind_alt; simpl;
    rewrite ?list_fmap_bind; auto using Forall_bind_ext.
  induction IH; f_equal'; auto with f_equal.
Qed.
Lemma ctree_Forall_not P Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ctree_Forall (not ∘ P) w → ¬ctree_Forall P w.
Proof.
  intros ??. apply Forall_not.
  erewrite ctree_flatten_length by eauto. eauto using bit_size_of_ne_0.
Qed.

(** ** Properties of the [union_reset] function *)
Lemma union_free_base Γ Δ w τb : (Γ,Δ) ⊢ w : baseT τb → union_free w.
Proof. inversion 1; constructor. Qed.
Lemma union_reset_typed Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → (Γ,Δ) ⊢ union_reset w : τ.
Proof.
  intros HΓ. revert w τ. refine (ctree_typed_ind _ _ _ _ _ _ _ _); simpl.
  * by typed_constructor.
  * intros ws τ Hws IH Hlen; typed_constructor; auto.
    + by rewrite fmap_length.
    + clear Hlen. induction IH; decompose_Forall_hyps; auto.
  * intros s wxbss τs Hs Hws IH ? Hindet Hlen; typed_constructor; eauto.
    + clear Hs Hlen Hindet. induction IH; decompose_Forall_hyps; auto.
    + clear Hindet. eapply Forall_fmap, Forall_impl; eauto.
    + elim Hindet; intros; constructor; simpl; auto.
    + rewrite <-Hlen, <-list_fmap_compose. by apply list_fmap_ext.
  * intros s i τs w xbs τ ??????? Hemp; simpl. typed_constructor; eauto.
    + eauto using ctree_flatten_valid.
    + by erewrite app_length, ctree_flatten_length by eauto.
  * typed_constructor; eauto.
Qed.
Lemma union_free_reset w : union_free w → union_reset w = w.
Proof.
  induction 1 as [|? ws _ IH|s wxbss _ IH|]
    using @union_free_ind_alt; f_equal'; auto.
  * by induction IH; f_equal'.
  * induction IH as [|[]]; f_equal'; auto with f_equal.
Qed.
Lemma union_reset_free w : union_free (union_reset w).
Proof.
  by induction w as [|ws IH|s wxbss IH| |]
    using ctree_ind_alt; simpl; constructor; apply Forall_fmap.
Qed.
Lemma union_free_unmapped w :
  ctree_valid w → ctree_Forall sep_unmapped w → union_free w.
Proof.
  induction 1 as [|? ws ? IH|? wxss ? IH| |] using @ctree_valid_ind_alt;
    intros; decompose_Forall_hyps; try constructor.
  * induction IH; decompose_Forall_hyps; auto.
  * induction IH; decompose_Forall_hyps; auto.
  * tauto.
Qed.

(** ** The [type_mask] function *)
Definition type_mask (Γ : env K) : type K → list bool := type_iter
  (**i TBase =>     *) (λ τb, replicate (bit_size_of Γ τb) false)
  (**i TArray =>    *) (λ _ n go, mjoin (replicate n go))
  (**i TCompound => *) (λ c s τs go,
    match c with
    | Struct_kind =>
       let τszs := field_bit_sizes Γ τs in
       mjoin (zip_with (λ τ sz, resize sz true (go τ)) τs τszs)
    | Union_kind => replicate (bit_size_of Γ (unionT s)) false
   end) Γ.
Lemma type_mask_base Γ τb : type_mask Γ τb = replicate (bit_size_of Γ τb) false.
Proof. done. Qed.
Lemma type_mask_array Γ τ n :
  type_mask Γ (τ.[n]) = mjoin (replicate n (type_mask Γ τ)).
Proof. unfold type_mask. by rewrite type_iter_array. Qed.
Lemma type_mask_compound Γ c s τs :
  ✓ Γ → Γ !! s = Some τs → type_mask Γ (compoundT{c} s)
  = match c with
    | Struct_kind =>
       let flds := field_bit_sizes Γ τs in
       mjoin (zip_with (λ τ sz, resize sz true (type_mask Γ τ)) τs flds)
    | Union_kind => replicate (bit_size_of Γ (unionT s)) false
    end.
Proof.
  intros HΓ Hs. unfold type_mask. erewrite (type_iter_compound (=)); try done.
  { by intros ????? ->. }
  clear s τs Hs. intros f g [] s τs _ _ Hfg; f_equal.
  induction (bit_size_of_fields Γ τs HΓ);
    decompose_Forall_hyps; f_equal; auto with congruence.
Qed.
Lemma type_mask_length Γ τ :
  ✓ Γ → ✓{Γ} τ → length (type_mask Γ τ) = bit_size_of Γ τ.
Proof.
  intros HΓ. revert τ. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb _. by rewrite type_mask_base, replicate_length.
  * intros τ n _ IH _. rewrite type_mask_array, bit_size_of_array, <-IH.
    induction n; simpl; rewrite ?app_length; auto.
  * intros [] s τs Hs _ _ _; erewrite !type_mask_compound by eauto; simpl.
    { erewrite bit_size_of_struct by eauto. clear Hs.
      induction (bit_size_of_fields _ τs HΓ); simpl; [done|].
      rewrite app_length, resize_length; auto. }
    by rewrite replicate_length.
Qed.

(** ** Properties of the [ctree_unflatten] function *)
Section array_unflatten.
  Context {A B} (f : list A → B).
  Lemma array_unflatten_weaken (g : list A → B) Γ1 Γ2 τ n xs :
    ✓ Γ1 → ✓{Γ1} τ → Γ1 ⊆ Γ2 → (∀ xs, f xs = g xs) →
    array_unflatten Γ1 f τ n xs = array_unflatten Γ2 g τ n xs.
  Proof.
    intros. unfold array_unflatten. erewrite bit_size_of_weaken by eauto.
    revert xs; induction n; intros; f_equal'; auto.
  Qed.
  Lemma array_unflatten_length Γ τ n xs :
    length (array_unflatten Γ f τ n xs) = n.
  Proof. revert xs. induction n; simpl; auto. Qed.
End array_unflatten.
Section struct_unflatten.
  Context {A B} (f : type K → list A → B).
  Lemma struct_unflatten_weaken (g : type K → list A → B) Γ1 Γ2 τs xs :
    ✓ Γ1 → ✓{Γ1}* τs → Γ1 ⊆ Γ2 →
    Forall (λ τ, ✓{Γ1} τ → ∀ xs, f τ xs = g τ xs) τs →
    struct_unflatten Γ1 f τs xs = struct_unflatten Γ2 g τs xs.
  Proof.
    unfold struct_unflatten. intros HΓ1 Hτs HΓ Hfg.
    erewrite <-(field_bit_sizes_weaken Γ1 Γ2) by eauto. revert xs.
    induction (bit_size_of_fields _ τs HΓ1); intros;
      decompose_Forall_hyps; f_equal'; eauto.
  Qed.
  Lemma struct_unflatten_type_of `{TypeOf (type K) B} Γ τs xs :
    ✓ Γ → (∀ τ xs, ✓{Γ} τ → type_of (f τ xs) = τ) → ✓{Γ}* τs →
    type_of <$> struct_unflatten Γ f τs xs = τs.
  Proof.
    intros HΓ ??. unfold struct_unflatten. revert xs.
    induction (bit_size_of_fields _ τs HΓ); intros;
      decompose_Forall_hyps; f_equal'; auto.
  Qed.
End struct_unflatten.

Lemma ctree_unflatten_base Γ τb xbs : ctree_unflatten Γ τb xbs = MBase τb xbs.
Proof. unfold ctree_unflatten. by rewrite type_iter_base. Qed.
Lemma ctree_unflatten_array Γ τ n xbs :
  ctree_unflatten Γ (τ.[n]) xbs =
    MArray τ (array_unflatten Γ (ctree_unflatten Γ τ) τ n xbs).
Proof. unfold ctree_unflatten. by rewrite type_iter_array. Qed.
Lemma ctree_unflatten_compound Γ c s τs xbs :
  ✓ Γ → Γ !! s = Some τs → ctree_unflatten Γ (compoundT{c} s) xbs
  = match c with
    | Struct_kind =>
       MStruct s (struct_unflatten Γ (λ τ xbs,
        let τsz := bit_size_of Γ τ in
        (ctree_unflatten Γ τ (take τsz xbs), pbit_indetify <$> drop τsz xbs)
       ) τs xbs)
    | Union_kind => MUnionAll s xbs
    end.
Proof.
  intros ? Hs. unfold ctree_unflatten.
  erewrite (type_iter_compound (pointwise_relation _ (=))); try done.
  { intros ???????; f_equal. by apply array_unflatten_weaken. }
  clear s τs Hs xbs. intros f g [] s τs Hs Hτs Hfg xbs; f_equal; auto.
  eapply struct_unflatten_weaken, Forall_impl; eauto with f_equal.
Qed.
Lemma ctree_unflatten_weaken Γ1 Γ2 τ xbs :
  ✓ Γ1 → ✓{Γ1} τ → Γ1 ⊆ Γ2 →
  ctree_unflatten Γ1 τ xbs = ctree_unflatten Γ2 τ xbs.
Proof.
  intros. apply (type_iter_weaken (pointwise_relation _ (=))); try done.
  { intros ???????; f_equal. by apply array_unflatten_weaken. }
  clear xbs. intros f g [] s τs Hs Hτs Hfg xbs; f_equal; auto.
  eapply struct_unflatten_weaken, Forall_impl; eauto 1.
  auto using bit_size_of_weaken with f_equal.
Qed.

Ltac solve_length := simplify_equality'; repeat first 
  [ rewrite take_length | rewrite drop_length | rewrite app_length
  | rewrite fmap_length | erewrite ctree_flatten_length by eauto
  | rewrite type_mask_length by eauto | rewrite replicate_length
  | rewrite bit_size_of_int | rewrite int_width_char | rewrite resize_length
  | rewrite insert_length | erewrite sublist_lookup_length by eauto
  | erewrite sublist_alter_length by eauto
  | match goal with
    | |- context [ bit_size_of ?Γ ?τ ] =>
      match goal with
        | H : Γ !! ?s = Some ?τs, H2 : ?τs !! _ = Some τ |- _ =>
          unless (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s)) by done;
          assert (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s))
            by eauto using bit_size_of_union_lookup
        end
    | H : Forall2 _ _ _ |- _ => apply Forall2_length in H
    end ]; first [omega | lia].
Hint Extern 0 (length _ = _) => solve_length.
Hint Extern 0 (_ = length _) => solve_length.
Hint Extern 0 (_ ≤ length _) => solve_length.
Hint Extern 0 (length _ ≤ _) => solve_length.

Lemma ctree_unflatten_typed Γ Δ τ xbs :
  ✓ Γ → ✓{Γ} τ → ✓{Γ,Δ}* xbs → length xbs = bit_size_of Γ τ →
  (Γ,Δ) ⊢ ctree_unflatten Γ τ xbs : τ.
Proof.
  intros HΓ Hτ. revert τ Hτ xbs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τ ? xbs ??. rewrite ctree_unflatten_base. by typed_constructor.
  * intros τ n Hτ IH Hn xbs Hxbs.
    rewrite ctree_unflatten_array, bit_size_of_array.
    intros Hxbs'. typed_constructor; auto using array_unflatten_length.
    clear Hn. revert xbs Hxbs Hxbs'. induction n; simpl; auto.
  * intros [] s τs Hs Hτs IH Hτs_len xbs Hxbs;
      erewrite ctree_unflatten_compound, ?bit_size_of_struct by eauto;
      intros Hxbs'; simpl; typed_constructor; eauto.
    + unfold struct_unflatten. clear Hs Hτs Hτs_len. revert xbs Hxbs Hxbs'.
      induction (bit_size_of_fields Γ τs HΓ);
        intros; decompose_Forall_hyps; constructor; eauto.
    + clear Hs IH Hτs Hτs_len Hxbs'. unfold struct_unflatten. revert xbs Hxbs.
      induction (bit_size_of_fields _ τs HΓ); constructor;
        simpl; auto using pbits_indetify_valid.
    + clear Hs IH Hτs Hτs_len Hxbs Hxbs'. unfold struct_unflatten. revert xbs.
      induction (bit_size_of_fields _ τs HΓ); constructor;
        simpl; auto using pbits_indetify_idempotent.
    + clear Hs IH Hτs Hτs_len Hxbs.
      unfold struct_unflatten, field_bit_padding. revert xbs Hxbs'.
      induction (bit_size_of_fields _ τs HΓ); intros; f_equal'; auto.
Qed.
Lemma ctree_unflatten_type_of Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → type_of (ctree_unflatten Γ τ xbs) = τ.
Proof.
  intros HΓ Hτ. revert τ Hτ xbs. refine (type_env_ind _ HΓ _ _ _ _).
  * done.
  * intros τ n _ IH ? xbs. rewrite ctree_unflatten_array; simpl.
    destruct n; simplify_equality'. by rewrite array_unflatten_length.
  * by intros [] s τs ? _ _ _ xbs; erewrite ctree_unflatten_compound by eauto.
Qed.
Lemma ctree_unflatten_union_free Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → union_free (ctree_unflatten Γ τ xbs).
Proof.
  intros HΓ Hτ. revert τ Hτ xbs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb _ xbs. rewrite ctree_unflatten_base. constructor.
  * intros τ n _ IH _ xbs. rewrite ctree_unflatten_array. constructor.
    revert xbs. elim n; simpl; constructor; auto.
  * intros [] s τs Hs _ IH _ xbs;
      erewrite !ctree_unflatten_compound by eauto; constructor.
    clear Hs. unfold struct_unflatten. revert xbs.
    induction (bit_size_of_fields _ τs HΓ); intros;
      decompose_Forall_hyps; constructor; eauto.
Qed.
Lemma ctree_unflatten_flatten Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ctree_unflatten Γ τ (ctree_flatten w) = union_reset w.
Proof.
  intros HΓ. revert w τ. refine (ctree_typed_ind _ _ _ _ _ _ _ _); simpl.
  * intros. by rewrite ctree_unflatten_base.
  * intros ws τ ? IH _. rewrite ctree_unflatten_array. f_equal.
    induction IH; [done |]; intros; decompose_Forall_hyps; auto.
    rewrite take_app_alt, drop_app_alt by auto. f_equal; auto.
  * intros s wxbss τs Hs Hws IH _ Hindet Hlen.
    erewrite ctree_unflatten_compound by eauto; f_equal'. clear Hs.
    revert wxbss Hindet Hlen Hws IH. unfold struct_unflatten, field_bit_padding.
    induction (bit_size_of_fields _ τs HΓ);
      intros [|[] ?] ????; decompose_Forall_hyps; [done|].
    rewrite ?take_app_alt, ?drop_app_alt by auto. repeat f_equal; auto.
  * intros. by erewrite ctree_unflatten_compound by eauto.
  * intros. by erewrite ctree_unflatten_compound by eauto.
Qed.
Lemma ctree_flatten_unflatten_le Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → length xbs ≤ bit_size_of Γ τ →
  ctree_flatten (ctree_unflatten Γ τ xbs)
  = mask pbit_indetify (type_mask Γ τ) xbs.
Proof.
  intros HΓ Hτ. revert τ Hτ xbs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros. by rewrite ctree_unflatten_base, type_mask_base, mask_false.
  * intros τ n ? IH _ xbs.
    rewrite ctree_unflatten_array, bit_size_of_array, type_mask_array; simpl.
    revert xbs. induction n as [|n IHn]; intros xbs ?; simplify_equality'.
    { symmetry; apply nil_length_inv; lia. }
    by rewrite IH, IHn, mask_app, type_mask_length by auto.
  * intros [] s τs Hs Hτs IH _ xbs; erewrite ctree_unflatten_compound,
      ?type_mask_compound, ?bit_size_of_struct, ?mask_false by eauto; eauto.
    clear Hs; simpl. revert xbs IH. unfold struct_unflatten.
    induction (bit_size_of_fields _ τs HΓ) as [|τ sz τs szs ?? IHτ]; simpl.
    { intros [|??] _ ?; simpl in *; auto with lia. }
    intros xbs. rewrite Forall_cons. intros [IH ?] ?; decompose_Forall_hyps.
    by rewrite IH, IHτ, mask_app, resize_length, resize_ge, mask_app,
      type_mask_length, mask_true by eauto.
Qed.
Lemma ctree_flatten_unflatten Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → length xbs = bit_size_of Γ τ →
  ctree_flatten (ctree_unflatten Γ τ xbs)
  = mask pbit_indetify (type_mask Γ τ) xbs.
Proof. intros. apply ctree_flatten_unflatten_le; auto with lia. Qed.
Lemma ctree_mask_flatten Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ →
  mask pbit_indetify (type_mask Γ τ) (ctree_flatten w) = ctree_flatten w.
Proof.
  intros. by erewrite <-ctree_flatten_unflatten,
    ctree_unflatten_flatten, ctree_flatten_union_reset by eauto.
Qed.
Lemma ctree_unflatten_Forall_le (P : pbit K → Prop) Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → (∀ xb, P xb → P (pbit_indetify xb)) → Forall P xbs →
  length xbs ≤ bit_size_of Γ τ → ctree_Forall P (ctree_unflatten Γ τ xbs).
Proof.
  intros ??? Hxbs Hlen. rewrite ctree_flatten_unflatten_le by done.
  generalize (type_mask Γ τ). clear Hlen.
  induction Hxbs; intros [|[] ?]; simpl; auto.
Qed.
Lemma ctree_unflatten_Forall (P : pbit K → Prop) Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → (∀ xb, P xb → P (pbit_indetify xb)) → Forall P xbs →
  length xbs = bit_size_of Γ τ → ctree_Forall P (ctree_unflatten Γ τ xbs).
Proof. intros. apply ctree_unflatten_Forall_le; auto with lia. Qed.
Lemma ctree_merge_unflatten {B : Set} Γ (h : pbit K → B → pbit K) xbs ys τ :
  ✓ Γ → ✓{Γ} τ → length xbs = bit_size_of Γ τ →
  zip_with h (pbit_indetify <$> xbs) ys = pbit_indetify <$> zip_with h xbs ys →
  ctree_merge true h (ctree_unflatten Γ τ xbs) ys
  = ctree_unflatten Γ τ (zip_with h xbs ys).
Proof.
  intros HΓ Hτ Hle. revert τ Hτ xbs ys Hle. refine (type_env_ind _ HΓ _ _ _ _).
  * intros. by rewrite !ctree_unflatten_base.
  * intros τ n ? IH _ xbs ys; rewrite bit_size_of_array,
      !ctree_unflatten_array; intros Hxbs Hh; f_equal'.
    revert xbs ys Hxbs Hh. induction n as [|n IHn]; intros; simpl;
      rewrite ?ctree_flatten_unflatten_le, ?zip_with_take, ?zip_with_drop,
      ?mask_length, ?take_length_le by auto; f_equal; auto.
    + apply IH; auto. by rewrite !fmap_take, <-!zip_with_take, fmap_take, Hh.
    + apply IHn; auto. by rewrite !fmap_drop, <-!zip_with_drop, fmap_drop, Hh.
  * intros [] s τs Hs Hτs IH _ xbs ys; erewrite ?bit_size_of_struct,
      !ctree_unflatten_compound by eauto; intros Hxbs Hh; f_equal'.
    clear Hs. revert xbs ys Hxbs Hh. unfold struct_unflatten. revert IH.
    induction (bit_size_of_fields _ τs HΓ) as [|τ sz τs szs ?? IHτs]; [done|].
    rewrite Forall_cons; intros [IH ?]; intros; decompose_Forall_hyps;
      rewrite ?ctree_flatten_unflatten_le, ?zip_with_take, ?zip_with_drop,
      ?fmap_length, ?drop_length, ?mask_length, ?take_length_le, ?take_take,
      ?Min.min_l, ?take_drop_commute, ?drop_drop, ?le_plus_minus_r by auto;
      repeat f_equal; auto.
    + apply IH; auto. by rewrite !fmap_take, <-!zip_with_take, fmap_take, Hh.
    + by rewrite !fmap_drop, !fmap_take, <-!zip_with_drop,
        <-!zip_with_take, fmap_drop, fmap_take, Hh.
    + apply IHτs; auto. by rewrite !fmap_drop, <-!zip_with_drop, fmap_drop, Hh.
Qed.

(** ** Properties of the [ctree_new] function *)
Lemma ctree_new_base Γ xb τb :
  ctree_new Γ xb τb = MBase τb (replicate (bit_size_of Γ τb) xb).
Proof. done. Qed.
Lemma ctree_new_array Γ xb τ n :
  ctree_new Γ xb (τ.[n]) = MArray τ (replicate n (ctree_new Γ xb τ)).
Proof.
  unfold ctree_new; rewrite ctree_unflatten_array, bit_size_of_array; f_equal.
  by induction n; f_equal'; rewrite ?take_replicate_plus, ?drop_replicate_plus.
Qed.
Lemma ctree_new_compound Γ xb c s τs :
  ✓ Γ → Γ !! s = Some τs → ctree_new Γ xb (compoundT{c} s)
  = match c with
    | Struct_kind => MStruct s (zip (ctree_new Γ xb <$> τs)
       (flip replicate (pbit_indetify xb) <$> field_bit_padding Γ τs))
    | Union_kind => MUnionAll s (replicate (bit_size_of Γ (unionT s)) xb)
    end.
Proof.
  intros HΓ Hs; unfold ctree_new; erewrite ctree_unflatten_compound by eauto.
  destruct c; f_equal. erewrite ?bit_size_of_struct by eauto; clear Hs.
  unfold struct_unflatten, field_bit_padding.
  by induction (bit_size_of_fields _ τs HΓ); decompose_Forall_hyps;
    rewrite ?take_replicate_plus, ?drop_replicate_plus, ?take_replicate,
    ?drop_replicate, ?Min.min_l, ?fmap_replicate by done; repeat f_equal.
Qed.
Lemma ctree_new_weaken Γ1 Γ2 xb τ :
  ✓ Γ1 → ✓{Γ1} τ → Γ1 ⊆ Γ2 → ctree_new Γ1 xb τ = ctree_new Γ2 xb τ.
Proof.
  intros. unfold ctree_new.
  by erewrite ctree_unflatten_weaken, bit_size_of_weaken by eauto.
Qed.
Lemma ctree_news_weaken Γ1 Γ2 xb τs :
  ✓ Γ1 → ✓{Γ1}* τs → Γ1 ⊆ Γ2 → ctree_new Γ1 xb <$> τs = ctree_new Γ2 xb <$> τs.
Proof. induction 2; intros; f_equal'; eauto using ctree_new_weaken. Qed.
Lemma ctree_new_Forall (P : pbit K → Prop) Γ xb τ :
  ✓ Γ → ✓{Γ} τ → P xb → P (pbit_indetify xb) → ctree_Forall P (ctree_new Γ xb τ).
Proof.
  intros. unfold ctree_new. rewrite ctree_flatten_unflatten_le by done.
  generalize (type_mask Γ τ).
  induction (bit_size_of Γ τ); intros [|[]?]; simpl; constructor; auto.
Qed.
Lemma ctree_new_type_of Γ xb τ :
  ✓ Γ → ✓{Γ} τ → type_of (ctree_new Γ xb τ) = τ.
Proof. by apply ctree_unflatten_type_of. Qed.
Lemma ctree_new_typed Γ Δ xb τ :
  ✓ Γ → ✓{Γ} τ → ✓{Γ,Δ} xb → (Γ,Δ) ⊢ ctree_new Γ xb τ : τ.
Proof. intros; apply ctree_unflatten_typed; auto using replicate_length. Qed.
Lemma ctree_new_union_free Γ xb τ: ✓ Γ → ✓{Γ} τ → union_free (ctree_new Γ xb τ).
Proof. by apply ctree_unflatten_union_free. Qed.
Lemma ctree_flatten_new Γ τ xb :
  ✓ Γ → ✓{Γ} τ → pbit_indetify xb = xb →
  ctree_flatten (ctree_new Γ xb τ) = replicate (bit_size_of Γ τ) xb.
Proof.
  intros; unfold ctree_new; rewrite ctree_flatten_unflatten by done.
  generalize (type_mask Γ τ).
  induction (bit_size_of _ _); intros [|[] ?]; f_equal'; auto.
Qed.
Lemma ctree_flatten_replicate_new Γ τ n xb :
  ✓ Γ → ✓{Γ} τ → pbit_indetify xb = xb →
  replicate n (ctree_new Γ xb τ) ≫= ctree_flatten
  = replicate (n * bit_size_of Γ τ) xb.
Proof.
  intros; induction n as [|n IH]; csimpl; auto.
  by rewrite replicate_plus, ctree_flatten_new, IH by done.
Qed.

(** ** The map operation *)
Lemma ctree_map_typed Γ Δ h w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ✓{Γ,Δ}* (h <$> ctree_flatten w) →
  (∀ xb, ✓{Γ,Δ} xb → sep_unmapped (h xb) → sep_unmapped xb) →
  (∀ xb, pbit_indetify xb = xb → pbit_indetify (h xb) = h xb) →
  (Γ,Δ) ⊢ ctree_map h w : τ.
Proof.
  intros ? Hw Hw' ??. revert w τ Hw Hw'. assert (∀ xbs,
    pbit_indetify <$> xbs = xbs → pbit_indetify <$> h <$> xbs = h <$> xbs).
  { induction xbs; intros; simplify_equality'; f_equal; auto. }
  assert (∀ xbs,
    ✓{Γ,Δ}* xbs → Forall sep_unmapped (h <$> xbs) → Forall sep_unmapped xbs).
  { induction 1; intros; decompose_Forall_hyps; eauto. }
  refine (ctree_typed_ind _ _ _ _ _ _ _ _); simpl.
  * typed_constructor; auto.
  * intros ws τ _ IH Hlen Hw'. typed_constructor; auto. clear Hlen.
    revert Hw'. induction IH; csimpl; rewrite ?fmap_app; intros;
      decompose_Forall_hyps; constructor; auto.
  * intros s wxbss τs Hs _ IH Hxss Hindet Hlen Hw'.
    typed_constructor; eauto.
    + revert Hw'. elim IH; [|intros [??] ???]; csimpl; rewrite ?fmap_app;
        intros; decompose_Forall_hyps; auto.
    + revert Hw'. elim Hxss; [|intros [??] ???]; csimpl; rewrite ?fmap_app;
        intros; decompose_Forall_hyps; auto.
    + elim Hindet; intros; constructor; simpl; auto.
    + rewrite <-Hlen. elim wxbss; intros; f_equal'; auto.
  * intros s i τs w xbs τ; rewrite fmap_app; intros; decompose_Forall_hyps.
    typed_constructor; eauto using ctree_flatten_valid; try solve_length.
    rewrite ctree_flatten_map; intuition eauto using ctree_flatten_valid.
  * typed_constructor; eauto.
Qed.
Lemma ctree_map_type_of h w : type_of (ctree_map h w) = type_of w.
Proof. destruct w; simpl; unfold MUnion'; repeat case_decide; auto. Qed.

(** ** Lookup operation *)
Lemma ctree_lookup_nil Γ : lookupE Γ (@nil (ref_seg K)) = (@Some (mtree K)).
Proof. done. Qed.
Lemma ctree_lookup_cons Γ rs r :
  lookupE Γ (rs :: r) = λ w : mtree K, w !!{Γ} r ≫= lookupE Γ rs.
Proof. done. Qed.
Lemma ctree_lookup_app Γ r1 r2 w :
  w !!{Γ} (r1 ++ r2) = (w !!{Γ} r2) ≫= lookupE Γ r1.
Proof.
  induction r1 as [|rs1 r1 IH]; simpl; [by destruct (w !!{_} r2)|].
  by rewrite ctree_lookup_cons, IH, option_bind_assoc.
Qed.
Lemma ctree_lookup_snoc Γ r rs w :
  w !!{Γ} (r ++ [rs]) = (w !!{Γ} rs) ≫= lookupE Γ r.
Proof. apply ctree_lookup_app. Qed.
Lemma ctree_lookup_seg_le Γ w rs1 rs2 w' :
  w !!{Γ} rs1 = Some w' → rs1 ⊆ rs2 → w !!{Γ} rs2 = Some w'.
Proof.
  destruct 2 as [| |?? [][]]; simpl in *; intuition.
  destruct w; simplify_option_equality; auto.
Qed.
Lemma ctree_lookup_le Γ w r1 r2 w' :
  w !!{Γ} r1 = Some w' → r1 ⊆* r2 → w !!{Γ} r2 = Some w'.
Proof.
  intros Hw Hr; revert w' Hw. induction Hr; intros w'; [done|].
  rewrite !ctree_lookup_cons, !bind_Some; intros (?&?&?);
    eauto using ctree_lookup_seg_le.
Qed.
Lemma ctree_lookup_seg_freeze_proper Γ q1 q2 w rs1 rs2 w1 w2 :
  w !!{Γ} rs1 = Some w1 → w !!{Γ} rs2 = Some w2 →
  freeze q1 rs1 = freeze q2 rs2 → w1 = w2.
Proof. intros. by destruct w, rs1, rs2; simplify_option_equality. Qed.
Lemma ctree_lookup_freeze_proper Γ q1 q2 w r1 r2 w1 w2 :
  w !!{Γ} r1 = Some w1 → w !!{Γ} r2 = Some w2 →
  freeze q1 <$> r1 = freeze q2 <$> r2 → w1 = w2.
Proof.
  revert r2 w1 w2. induction r1 as [|rs1 r1 IH]; intros [|rs2 r2] ??; try done.
  { intros. by simplify_equality. }
  rewrite !ctree_lookup_cons; intros; simplify_option_equality.
  efeed pose proof IH; eauto. subst. eauto using ctree_lookup_seg_freeze_proper.
Qed.
Lemma ctree_lookup_seg_inv P Γ rs w w' :
  w !!{Γ} rs = Some w' →
  match rs, w with
  | RArray i τ n, MArray τ' ws =>
     (∀ w'', τ' = τ → n = length ws → ws !! i = Some w'' → P w'') → P w'
  | RStruct i s, MStruct s' wxbss =>
     (∀ w'' xs, s = s' → wxbss !! i = Some (w'', xs) → P w'') → P w'
  | RUnion i s q, MUnion s' j w'' xs =>
     (s = s' → i = j → P w'') →
     (∀ τs τ, s = s' → i ≠ j → q = false →
       Γ !! s = Some τs → τs !! i = Some τ →
       ctree_unshared w'' → Forall sep_unshared xs →
       P (ctree_unflatten Γ τ (take (bit_size_of Γ τ)
          (ctree_flatten w'' ++ xs)))) →
     P w'
  | RUnion i s _, MUnionAll s' xs =>
     (∀ τs τ, s = s' → Γ !! s = Some τs → τs !! i = Some τ →
       Forall sep_unshared xs →
       P (ctree_unflatten Γ τ (take (bit_size_of Γ τ) xs))) →
     P w'
  | _, _ => P w'
  end.
Proof.
  destruct rs, w; intros; simplify_option_equality;
    repeat match goal with p : prod _ _ |- _ => destruct p end; eauto.
Qed.

Lemma ctree_lookup_seg_weaken Γ1 Γ2 rs w w' :
  ✓ Γ1 → Γ1 ⊆ Γ2 → w !!{Γ1} rs = Some w' → w !!{Γ2} rs = Some w'.
Proof.
  intros ?? Hrs. by destruct w, rs; pattern w';
    apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); intros;
    simplify_option_equality by eauto using lookup_compound_weaken;
    erewrite <-?(bit_size_of_weaken Γ1 Γ2),
      <-?(ctree_unflatten_weaken Γ1 Γ2) by eauto.
Qed.
Lemma ctree_lookup_weaken Γ1 Γ2 r w w' :
  ✓ Γ1 → Γ1 ⊆ Γ2 → w !!{Γ1} r = Some w' → w !!{Γ2} r = Some w'.
Proof.
  intros ??. revert w'. induction r as [|rs r IH]; intros w'; [done|].
  rewrite !ctree_lookup_cons; intros; simplify_option_equality;
    eauto using ctree_lookup_seg_weaken.
Qed.
Lemma ctree_lookup_seg_union_free Γ w rs w' :
  ✓ Γ → union_free w → w !!{Γ} rs = Some w' → union_free w'.
Proof.
  intros ? Hw Hrs; destruct Hw, rs; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs).
  * by intros; decompose_Forall_hyps.
  * by intros; decompose_Forall_hyps.
  * eauto using ctree_unflatten_union_free, env_valid_lookup_singleton.
Qed.
Lemma ctree_lookup_union_free Γ w r w' :
  ✓ Γ → union_free w → w !!{Γ} r = Some w' → union_free w'.
Proof.
  intros HΓ. revert w. induction r using rev_ind; intros w Hw Hr;
    rewrite ?ctree_lookup_snoc in Hr; simplify_option_equality;
    simplify_type_equality; eauto using ctree_lookup_seg_union_free.
Qed.
Lemma ctree_lookup_seg_Some Γ Δ w τ rs w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' →
  ∃ σ, Γ ⊢ rs : τ ↣ σ ∧ (Γ,Δ) ⊢ w' : σ.
Proof.
  intros ? Hw Hrs; destruct rs as [i τ' n|i|i]; destruct Hw as
    [τ xbs|ws|s wxbss τs ? Hws|s j τs w xbs τ|s τs xbs];
    change (ctree_typed' Γ Δ) with (typed (Γ,Δ)) in *;
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
  * intros w'' -> -> ?. exists τ'. decompose_Forall_hyps.
    repeat constructor; eauto using lookup_lt_is_Some_1.
  * intros w'' xbs -> ?.
    destruct (Forall2_lookup_l _ _ _ i (w'',xbs) Hws) as [σ [??]]; eauto.
    exists σ; repeat econstructor; eauto.
  * intros -> ->. exists τ; repeat econstructor; eauto.
  * intros ? τ' ???????; simplify_equality'. exists τ'; repeat econstructor;
      eauto 6 using ctree_unflatten_typed, ctree_flatten_valid.
  * intros ?? -> ???; simplify_equality'.
    exists τ; repeat econstructor; eauto using ctree_unflatten_typed.
Qed.
Lemma ctree_lookup_seg_Some_type_of Γ Δ w τ rs w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' → (Γ,Δ) ⊢ w' : type_of w'.
Proof.
  intros. destruct (ctree_lookup_seg_Some Γ Δ w τ rs w')
    as (?&?&?); eauto using type_of_typed.
Qed.
Lemma ctree_lookup_Some Γ Δ w τ r w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' →
  ∃ σ, Γ ⊢ r : τ ↣ σ ∧ (Γ,Δ) ⊢ w' : σ.
Proof.
  intros HΓ. revert w τ.
  induction r as [|rs r IH] using rev_ind; intros w τ Hvτ Hr.
  { simplify_type_equality'. eexists; split; [econstructor |]; eauto. }
  rewrite ctree_lookup_snoc in Hr. simplify_option_equality.
  edestruct ctree_lookup_seg_Some as (?&?&?); eauto.
  edestruct IH as (?&?&?); eauto.
  eexists; split; [eapply ref_typed_snoc |]; eauto.
Qed.
Lemma ctree_lookup_Some_type_of Γ Δ w τ r w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' → (Γ,Δ) ⊢ w' : type_of w'.
Proof.
  intros. destruct (ctree_lookup_Some Γ Δ w τ r w')
    as (?&?&?); eauto using type_of_typed.
Qed.
Lemma ctree_lookup_seg_typed Γ Δ w τ rs w' σ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' → Γ ⊢ rs : τ ↣ σ → (Γ,Δ) ⊢ w' :σ.
Proof.
  intros HΓ Hvτ Hw ?. by destruct (ctree_lookup_seg_Some _ _ _ _ _ _ HΓ Hvτ Hw)
    as (σ'&Hrσ'&?); simplify_type_equality.
Qed.
Lemma ctree_lookup_typed Γ Δ w τ r w' σ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' → Γ ⊢ r : τ ↣ σ → (Γ,Δ) ⊢ w' : σ.
Proof.
  intros HΓ Hvτ Hw' ?. by destruct (ctree_lookup_Some _ _ _ _ _ _ HΓ Hvτ Hw')
    as (σ'&Hrσ'&?); simplify_type_equality.
Qed.
Lemma ctree_lookup_seg_Forall (P : pbit K → Prop) Γ w rs w' :
  ✓ Γ → (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} rs = Some w' → ctree_Forall P w'.
Proof.
  intros ??.
  assert (∀ βs xbs, Forall P xbs → Forall P (mask pbit_indetify βs xbs)).
  { intros βs xbs Hxbs. revert βs. induction Hxbs; intros [|[]]; simpl; auto. }
  intros Hw Hrs; destruct w, rs; simpl in Hw; rewrite ?Forall_bind in Hw;
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs;
    intros; decompose_Forall_hyps; eauto 7 using ctree_unflatten_Forall_le.
Qed.
Lemma ctree_lookup_Forall (P : pbit K → Prop) Γ w r w' :
  ✓ Γ → (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} r = Some w' → ctree_Forall P w'.
Proof.
  intros HΓ ?. revert w. induction r as [|rs r] using rev_ind;
    intros w; rewrite ?ctree_lookup_snoc; intros; simplify_option_equality;
    simplify_type_equality; eauto using ctree_lookup_seg_Forall.
Qed.
Lemma ctree_lookup_Forall_typed (P : pbit K → Prop) Γ Δ w τ r w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → (∀ xb, ✓{Γ,Δ} xb → P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} r = Some w' → ctree_Forall P w'.
Proof.
  intros. eapply Forall_and_l with ✓{Γ,Δ}, ctree_lookup_Forall; eauto.
  * intros ? [??]; eauto using pbit_indetify_valid.
  * rewrite Forall_and; eauto using ctree_flatten_valid.
Qed.
Lemma ctree_new_lookup_seg Γ τ x rs σ :
  ✓ Γ → sep_unshared x → ✓{Γ} τ →
  Γ ⊢ rs : τ ↣ σ → ctree_new Γ x τ !!{Γ} rs = Some (ctree_new Γ x σ).
Proof.
  destruct 4 as [τ n i|s i τs τ Hs Hτs|s i q τs τ].
  * rewrite ctree_new_array; simplify_option_equality.
    by rewrite lookup_replicate by done.
  * erewrite ctree_new_compound by eauto; simplify_option_equality.
    by rewrite <-list_lookup_fmap, fst_zip, list_lookup_fmap, Hτs
      by (by rewrite !fmap_length, field_bit_padding_length).
  * erewrite ctree_new_compound by eauto; simplify_option_equality by eauto.
    by rewrite take_replicate,Min.min_l by eauto using bit_size_of_union_lookup.
Qed.
Lemma ctree_new_lookup Γ x τ r σ :
  ✓ Γ → sep_unshared x → ✓{Γ} τ →
  Γ ⊢ r : τ ↣ σ → ctree_new Γ x τ !!{Γ} r = Some (ctree_new Γ x σ).
Proof.
  induction 4 as [|r rs τ1 τ2 τ3 ?? IH] using @ref_typed_ind; [done|].
  rewrite ctree_lookup_cons, IH; simpl;
    eauto using ctree_new_lookup_seg, ref_typed_type_valid.
Qed.
Lemma ctree_lookup_seg_unfreeze_exists Γ Δ w τ rs σ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ctree_unshared w →
  Γ ⊢ rs : τ ↣ σ → ∃ w', w !!{Γ} freeze false rs = Some w'.
Proof.
  destruct 2 as [|ws τ|s wxbss τs| | ];
    inversion 2; decompose_Forall_hyps; simplify_option_equality; eauto.
  by apply lookup_lt_is_Some_2.
Qed.
Lemma ctree_lookup_unfreeze_exists Γ Δ w τ r σ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ctree_unshared w →
  Γ ⊢ r : τ ↣ σ → ∃ w', w !!{Γ} (freeze false <$> r) = Some w'.
Proof.
  intros HΓ. revert w τ.
  induction r as [|rs r IH] using rev_ind; intros w τ Hwτ Hw Hr.
  { rewrite ref_typed_nil in Hr; subst. by exists w. }
  rewrite ref_typed_snoc in Hr; destruct Hr as (σ'&?&?).
  destruct (ctree_lookup_seg_unfreeze_exists Γ Δ w τ rs σ') as (w'&?); auto.
  destruct (IH w' σ') as (w''&?); eauto using ctree_lookup_seg_union_free,
    ctree_lookup_seg_Forall, ctree_lookup_seg_typed, pbit_indetify_unshared,
    ref_seg_typed_le, ref_seg_freeze_le_r.
  exists w''. rewrite fmap_app; csimpl.
  rewrite ctree_lookup_snoc. by simplify_option_equality.
Qed.
Lemma type_mask_ref_seg Γ τ rs σ :
  ✓ Γ → Γ ⊢ rs : τ ↣ σ → ✓{Γ} τ →
  take (bit_size_of Γ σ) (drop (ref_seg_object_offset Γ rs) (type_mask Γ τ))
  =.>* type_mask Γ σ.
Proof.
  intros HΓ Hrs Hτ.
  destruct Hrs as [τ i n Hin|s i τs τ Hs Hi|]; simplify_option_equality.
  * rewrite type_mask_array; apply reflexive_eq. revert i Hin.
    apply TArray_valid_inv_type in Hτ.
    induction n as [|n]; intros [|i] ?; simplify_equality'; rewrite ?drop_0,
      ?take_app_alt, <-?drop_drop, ?drop_app_alt by done; auto with lia.
  * erewrite type_mask_compound by eauto; simpl; apply reflexive_eq.
    assert (✓{Γ}* τs) as Hτs by eauto; revert i Hi Hτs. clear Hs Hτ.
    unfold field_bit_offset.
    induction (bit_size_of_fields _ τs HΓ); intros [|i] ??;
      decompose_Forall_hyps; rewrite <-?drop_drop, ?drop_app_alt, ?drop_0,
        ?resize_ge, <-?(associative_L (++)), ?take_app_alt by done; auto.
  * erewrite type_mask_compound by eauto; simpl.
    rewrite drop_0, take_replicate, Min.min_l by solve_length.
    by apply replicate_false.
Qed.
Lemma ctree_lookup_seg_flatten Γ Δ w τ rs w' τ' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' → (Γ,Δ) ⊢ w' : τ' →
  mask pbit_indetify (type_mask Γ τ') $ take (bit_size_of Γ τ') $
    drop (ref_seg_object_offset Γ rs) $ ctree_flatten w = ctree_flatten w'.
Proof.
  intros HΓ Hw Hrs Hw'. rewrite <-(type_of_correct (Γ,Δ) w' τ') by done.
  clear Hw'. revert w τ Hw Hrs. refine (ctree_typed_ind _ _ _ _ _ _ _ _).
  * by destruct rs.
  * intros ws τ Hws _ _ Hrs; destruct rs as [i| |]; pattern w';
      apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs.
    assert (∀ ws', (Γ,Δ) ⊢* ws' : τ →
      length (ws' ≫= ctree_flatten) = length ws' * bit_size_of Γ τ) as help.
    { induction 1; f_equal'; auto. }
    intros w <- -> ?; decompose_Forall_hyps; simplify_type_equality.
    rewrite <-(take_drop_middle ws i w), bind_app, bind_cons by done.
    rewrite drop_app_alt by (by rewrite help, take_length_le
      by eauto using Nat.lt_le_incl, lookup_lt_Some).
    by erewrite take_app_alt, ctree_mask_flatten by eauto.
  * intros s wxbss τs Hs Hws _ _ Hindet Hlen Hrs; destruct rs as [|i|];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    intros w xs -> Hi; destruct (Forall2_lookup_l (typed (Γ,Δ) ∘ fst)
      wxbss τs i (w,xs)) as (τ&Hi'&Hw); auto;
      simplify_option_equality; simplify_type_equality'.
    assert (field_bit_offset Γ τs i =
      length (take i wxbss ≫= λ wxs, ctree_flatten (wxs.1) ++ wxs.2)) as help2.
    { clear Hs Hi' Hw Hindet. apply lookup_lt_Some in Hi.
      unfold field_bit_padding, field_bit_offset in *.
      revert i wxbss Hi Hlen Hws. induction (bit_size_of_fields _ τs HΓ);
        intros [|?] ????; decompose_Forall_hyps;
        rewrite ?app_length; f_equal; auto; solve_length. }
    rewrite <-(take_drop_middle wxbss i (w,xs)), bind_app by done; csimpl.
    by erewrite drop_app_alt, <-(associative_L (++)), take_app_alt,
      ctree_mask_flatten by eauto.
  * intros s i τs w xs τ Hs Hτ ? _ _ Hindet ? _ Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    { intros -> ->; simplify_option_equality; simplify_type_equality.
      by erewrite drop_0, take_app_alt, ctree_mask_flatten by eauto. }
    intros ? τ'' -> ? -> ?? _ _; simplify_option_equality.
    rewrite ctree_unflatten_type_of by eauto.
    by rewrite ctree_flatten_unflatten by eauto.
  * intros s τs xs ? _ ? Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    intros ?? -> ?? _; simplify_option_equality.
    rewrite ctree_unflatten_type_of by eauto.
    by rewrite ctree_flatten_unflatten by eauto.
Qed.
Lemma ctree_lookup_flatten Γ Δ w τ r w' τ' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' → (Γ,Δ) ⊢ w' : τ' →
  mask pbit_indetify (type_mask Γ τ') $
    take (bit_size_of Γ τ') $
    drop (ref_object_offset Γ r) $ ctree_flatten w = ctree_flatten w'.
Proof.
  intros HΓ ?. unfold ref_object_offset.
  revert w' τ'. induction r as [|rs r IH]; intros w'' τ''.
  { intros; simplify_type_equality'.
    by erewrite drop_0, take_ge, ctree_mask_flatten by eauto. }
  rewrite ctree_lookup_cons; intros.
  destruct (w !!{Γ} r) as [w'|] eqn:?; simplify_equality'.
  destruct (ctree_lookup_Some Γ Δ w τ r w') as (τ'&?&?); auto.
  destruct (ctree_lookup_seg_Some Γ Δ w' τ' rs w'') as (?&?&?); auto.
  simplify_type_equality'.
  assert (ref_seg_object_offset Γ rs + bit_size_of Γ τ'' ≤ bit_size_of Γ τ')
    by eauto using ref_seg_object_offset_size'.
  rewrite Nat.add_comm, <-drop_drop, <-(Min.min_l (bit_size_of Γ τ'')
    (bit_size_of Γ τ' - ref_seg_object_offset Γ rs)), <-take_take,
    take_drop_commute, le_plus_minus_r by lia.
  by erewrite <-(mask_mask _ pbit_indetify), <-take_mask, <-drop_mask,
    IH, ctree_lookup_seg_flatten by eauto using type_mask_ref_seg.
Qed.
Lemma ctree_lookup_seg_merge {B : Set} Γ Δ
    (h : pbit K → B → pbit K) w ys τ rs w' τ' :
  ✓ Γ → (∀ xb y, h (pbit_indetify xb) y = pbit_indetify (h xb y)) →
  (∀ xb y, sep_unshared xb → sep_unshared (h xb y)) →
  (Γ,Δ) ⊢ w : τ → length ys = bit_size_of Γ τ →
  w !!{Γ} rs = Some w' → (Γ,Δ) ⊢ w' : τ' → ctree_merge true h w ys !!{Γ} rs
  = Some (ctree_merge true h w' (take (bit_size_of Γ τ')
     (drop (ref_seg_object_offset Γ rs) ys))).
Proof.
  intros HΓ ?? Hw Hlen Hrs Hw'.
  rewrite <-(type_of_correct (Γ,Δ) w' τ') by done.
  assert (∀ xbs ys,
   zip_with h (pbit_indetify <$> xbs) ys = pbit_indetify <$> zip_with h xbs ys).
  { induction xbs; intros [|??]; f_equal'; auto. }
  clear Hw'. revert w τ Hw Hlen Hrs. assert (∀ xbs ys,
    Forall sep_unshared xbs → Forall sep_unshared (zip_with h xbs ys)).
  { induction xbs; intros [|??] ?; decompose_Forall_hyps; auto. }
  refine (ctree_typed_ind _ _ _ _ _ _ _ _).
  * by destruct rs.
  * intros ws τ Hws _ _ _ Hrs. destruct rs as [i| |]; pattern w';
      apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs.
    intros w <- -> Hw; simplify_equality'.
    erewrite type_of_correct by (decompose_Forall_hyps; eauto).
    assert (length (ctree_merge_array (ctree_merge true h) ws ys) = length ws)
      as Hlen by (generalize ys; elim ws; intros; f_equal'; auto).
    simplify_option_equality; clear Hlen.
    revert i w ys Hw. induction Hws as [|w ws ?? IH];
      intros [|i] w' ys ?; simplify_equality'.
    { by erewrite ctree_flatten_length by eauto. }
    by erewrite IH, ctree_flatten_length, drop_drop by eauto.
  * intros s wxbss τs Hs Hws _ _ _ Hlen _ Hrs; destruct rs as [|i|];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs.
    intros w xbs -> Hwxbs; destruct (Forall2_lookup_l (typed (Γ,Δ) ∘ fst)
      wxbss τs i (w,xbs)) as (τ&Hτ&Hw); auto;
      simplify_option_equality; simplify_type_equality'.
    clear Hs Hw. revert wxbss i w xbs τ ys Hτ Hws Hlen Hwxbs.
    unfold field_bit_padding, field_bit_offset.
    induction (bit_size_of_fields _ τs HΓ) as [|τ sz τs szs ?? IH];
      intros [|[w' xbs'] wxbss] [|i] ??? ys ????; decompose_Forall_hyps.
    { by erewrite ctree_flatten_length by eauto. }
    erewrite IH, ctree_flatten_length, !drop_drop by eauto.
    do 4 f_equal; lia.
  * intros s i τs w xbs τ Hs Hτ ? _ _ Hindet ? _ ? Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    { intros -> ->; simplify_option_equality; simplify_type_equality.
      by erewrite ctree_flatten_length, drop_0 by eauto. }
    intros ? τ'' -> ? -> ????; simplify_equality'.
    rewrite ctree_flatten_merge; simplify_option_equality; f_equal.
    rewrite ctree_unflatten_type_of, ctree_merge_unflatten, drop_0 by eauto.
    by rewrite <-zip_with_app, zip_with_take, take_drop by auto.
  * intros s τs xs ? _ ? _ Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    intros ?? -> ???; simplify_option_equality; f_equal.
    rewrite ctree_unflatten_type_of by eauto.
    by rewrite ctree_merge_unflatten, drop_0, zip_with_take by eauto.
Qed.
Lemma ctree_lookup_merge {B : Set} Γ Δ
    (h : pbit K → B → pbit K) w ys τ r w' τ' :
  ✓ Γ → (∀ xb y, h (pbit_indetify xb) y = pbit_indetify (h xb y)) →
  (∀ xb y, sep_unshared xb → sep_unshared (h xb y)) →
  (Γ,Δ) ⊢ w : τ → length ys = bit_size_of Γ τ →
  w !!{Γ} r = Some w' → (Γ,Δ) ⊢ w' : τ' → ctree_merge true h w ys !!{Γ} r
  = Some (ctree_merge true h w' (take (bit_size_of Γ τ')
      (drop (ref_object_offset Γ r) ys))).
Proof.
  intros ?????. unfold ref_object_offset. revert w' τ'.
  induction r as [|rs r IH]; intros w'' τ''.
  { intros; simplify_type_equality'. by rewrite drop_0, take_ge by auto. }
  rewrite !ctree_lookup_cons; intros.
  destruct (w !!{Γ} r) as [w'|] eqn:?; simplify_equality'.
  destruct (ctree_lookup_Some Γ Δ w τ r w') as (τ'&?&?); auto.
  destruct (ctree_lookup_seg_Some Γ Δ w' τ' rs w'') as (?&?&?); auto.
  erewrite IH by eauto; simplify_type_equality'.
  assert (sum_list (ref_seg_object_offset Γ <$> r) + bit_size_of Γ τ'
    ≤ bit_size_of Γ τ) by (by apply ref_object_offset_size').
  assert (ref_seg_object_offset Γ rs + bit_size_of Γ τ'' ≤ bit_size_of Γ τ')
    by eauto using ref_seg_object_offset_size'.
  erewrite ctree_lookup_seg_merge by eauto; do 2 f_equal.
  rewrite <-drop_drop, !take_drop_commute, !drop_drop, take_take.
  repeat (lia || f_equal).
Qed.

(** ** Alter operation *)
Lemma ctree_alter_nil Γ g : ctree_alter Γ g [] = g.
Proof. done. Qed.
Lemma ctree_alter_cons Γ g rs r :
  ctree_alter Γ g (rs :: r) = ctree_alter Γ (ctree_alter_seg Γ g rs) r.
Proof. done. Qed.
Lemma ctree_alter_app Γ g w r1 r2 :
  ctree_alter Γ g (r1 ++ r2) w = ctree_alter Γ (ctree_alter Γ g r1) r2 w.
Proof.
  revert g. induction r1; simpl; intros; rewrite ?ctree_alter_cons; auto.
Qed.
Lemma ctree_alter_snoc Γ g w r rs :
  ctree_alter Γ g (r ++ [rs]) w = ctree_alter_seg Γ (ctree_alter Γ g r) rs w.
Proof. apply ctree_alter_app. Qed.
Lemma ctree_alter_seg_le Γ g rs1 rs2 :
  rs1 ⊆ rs2 → ctree_alter_seg Γ g rs1 = ctree_alter_seg Γ g rs2.
Proof. by destruct 1. Qed.
Lemma ctree_alter_le Γ g r1 r2 :
  r1 ⊆* r2 → ctree_alter Γ g r1 = ctree_alter Γ g r2.
Proof.
  intros Hr. revert g.
  induction Hr as [|rs1 rs2 r1 r2 ?? IH]; intros g; simpl; auto.
  by erewrite IH, ctree_alter_seg_le by eauto.
Qed.
Lemma ctree_alter_seg_ext Γ g1 g2 w rs :
  (∀ w', g1 w' = g2 w') → ctree_alter_seg Γ g1 rs w = ctree_alter_seg Γ g2 rs w.
Proof.
  intros. destruct rs, w; simpl; unfold default; simplify_option_equality;
    repeat case_match; f_equal; auto using list_fmap_ext, list_alter_ext.
  by apply list_alter_ext; [intros [??] ?; f_equal'; auto|].
Qed.
Lemma ctree_alter_ext Γ g1 g2 w r :
  (∀ w, g1 w = g2 w) → ctree_alter Γ g1 r w = ctree_alter Γ g2 r w.
Proof.
  intros. revert w. induction r as [|rs r IH] using rev_ind; intros w; [done|].
  rewrite !ctree_alter_snoc. by apply ctree_alter_seg_ext.
Qed.
Lemma ctree_alter_seg_compose Γ g1 g2 w rs :
  ctree_alter_seg Γ (g1 ∘ g2) rs w
  = ctree_alter_seg Γ g1 rs (ctree_alter_seg Γ g2 rs w).
Proof.
  destruct w as [| |s wxbss| |], rs as [i|i|i]; simpl; unfold default;
    repeat (simplify_option_equality || case_match);
    f_equal; auto using list_alter_compose, list_fmap_compose.
  rewrite <-list_alter_compose. by apply list_alter_ext.
Qed.
Lemma ctree_alter_compose Γ g1 g2 w r :
  ctree_alter Γ (g1 ∘ g2) r w = ctree_alter Γ g1 r (ctree_alter Γ g2 r w).
Proof.
  intros. revert w. induction r as [|rs r IH] using rev_ind; intros w; [done|].
  rewrite !ctree_alter_snoc, <-ctree_alter_seg_compose.
  by apply ctree_alter_seg_ext.
Qed.
Lemma ctree_alter_seg_commute Γ g1 g2 w rs1 rs2 :
  rs1 ⊥ rs2 → ctree_alter_seg Γ g1 rs1 (ctree_alter_seg Γ g2 rs2 w)
  = ctree_alter_seg Γ g2 rs2 (ctree_alter_seg Γ g1 rs1 w).
Proof.
  destruct 1 as [|i1 i2 ? Hi], w as [| |? wxbss| |]; intros;
    simplify_option_equality; f_equal; auto using list_alter_commute.
Qed.
Lemma ctree_alter_commute Γ g1 g2 w r1 r2 :
  r1 ⊥ r2 → ctree_alter Γ g1 r1 (ctree_alter Γ g2 r2 w)
  = ctree_alter Γ g2 r2 (ctree_alter Γ g1 r1 w).
Proof.
  rewrite ref_disjoint_alt. intros (r1'&rs1'&r1''&r2'&rs2'&r2''&->&->&?&Hr).
  rewrite !ctree_alter_app, !ctree_alter_cons, !ctree_alter_nil.
  erewrite <-!(ctree_alter_le _ _ (freeze true <$> r1'')), Hr,
    !(ctree_alter_le _ _ (freeze true <$> r2'') r2'')
    by eauto using ref_freeze_le_l.
  rewrite <-!ctree_alter_compose. apply ctree_alter_ext; intros w'; simpl; auto.
  by apply ctree_alter_seg_commute.
Qed.
Lemma ctree_alter_lookup_seg_Forall (P : pbit K → Prop) Γ g w rs w' :
  ctree_Forall P (ctree_alter_seg Γ g rs w) →
  w !!{Γ} rs = Some w' → ctree_Forall P (g w').
Proof.
  intros Hgw Hrs. destruct w as [|τ ws|s wxbss|s i w xbs|], rs as [i'|i'|i'];
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs.
  * intros w -> -> Hw; simplify_equality'; rewrite Forall_bind in Hgw.
    apply (Forall_lookup_1 (λ w, ctree_Forall P w) (alter g i' ws) i'); auto.
    by rewrite list_lookup_alter, Hw.
  * intros w xbs -> Hwxbs; simplify_equality'; rewrite Forall_bind in Hgw.
    assert (alter (prod_map g id) i' wxbss !! i' = Some (g w, xbs)).
    { by rewrite list_lookup_alter, Hwxbs. }
    by decompose_Forall_hyps.
  * by intros; simplify_option_equality; decompose_Forall_hyps.
  * by intros; simplify_option_equality; decompose_Forall_hyps.
  * by intros; simplify_option_equality; decompose_Forall_hyps.
Qed.
Lemma ctree_alter_lookup_Forall (P : pbit K → Prop) Γ g w r w' :
  ctree_Forall P (ctree_alter Γ g r w) →
  w !!{Γ} r = Some w' → ctree_Forall P (g w').
Proof.
  revert g w. induction r as [|rs r IH] using @rev_ind.
  { intros g w. rewrite ctree_lookup_nil. naive_solver. }
  intros g w. rewrite ctree_alter_snoc, ctree_lookup_snoc.
  intros. destruct (w !!{Γ} rs) as [w''|] eqn:Hw''; simplify_equality'.
  eauto using ctree_alter_lookup_seg_Forall.
Qed.
Lemma ctree_alter_seg_Forall (P : pbit K → Prop) Γ g w rs w' :
  (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} rs = Some w' → ctree_Forall P (g w') →
  ctree_Forall P (ctree_alter_seg Γ g rs w).
Proof.
  intros ?. assert (∀ xbs, Forall P xbs → Forall P (pbit_indetify <$> xbs)).
  { induction 1; simpl; auto. }
  intros Hw Hrs. destruct w as [|τ ws|s wxbss|s i w xbs|], rs as [i'|i'|i'];
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs.
  * intros w -> -> ??; simplify_equality'. rewrite Forall_bind in Hw |- *.
    apply Forall_alter; intros; simplify_equality; auto.
  * intros w xbs -> ??; simplify_equality'. rewrite Forall_bind in Hw |- *.
    apply Forall_alter; intros; decompose_Forall_hyps; auto.
  * intros; simplify_option_equality; decompose_Forall_hyps; auto.
  * intros; simplify_option_equality; decompose_Forall_hyps; auto.
  * intros; simplify_option_equality; decompose_Forall_hyps; auto.
Qed.
Lemma ctree_alter_Forall (P : pbit K → Prop) Γ g w r w' :
  ✓ Γ → (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} r = Some w' → ctree_Forall P (g w') →
  ctree_Forall P (ctree_alter Γ g r w).
Proof.
  intros ??. revert g w. induction r as [|rs r IH] using @rev_ind.
  { intros g w. rewrite ctree_lookup_nil. naive_solver. }
  intros g w. rewrite ctree_alter_snoc, ctree_lookup_snoc.
  intros. destruct (w !!{Γ} rs) as [w''|] eqn:Hw''; simplify_equality'.
  eauto using ctree_alter_seg_Forall, ctree_lookup_seg_Forall.
Qed.
Lemma ctree_alter_seg_typed Γ Δ g w rs τ w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' →
  (Γ,Δ) ⊢ g w' : type_of w' → ¬ctree_unmapped (g w') →
  (Γ,Δ) ⊢ ctree_alter_seg Γ g rs w : τ.
Proof.
  intros HΓ Hw Hrs.
  destruct rs as [i|i|i], Hw as [|τ ? ws|s wxbss τs ??? Hindet Hlen| |];
    change (ctree_typed' Γ Δ) with (typed (Γ,Δ)) in *;
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
  * intros; simplify_option_equality.
    typed_constructor; auto using alter_length.
    apply (Forall_alter _ g _ i); auto. by intros; simplify_type_equality'.
  * intros; simplify_option_equality. typed_constructor; eauto.
    + apply Forall2_alter_l; auto 1. by intros [] ????; simplify_type_equality'.
    + apply Forall_alter; auto.
    + apply Forall_alter; auto.
    + rewrite <-Hlen. generalize i. elim wxbss; [done|].
      intros [??] wxbss' ? [|?]; f_equal'; auto.
  * intros; simplify_option_equality. typed_constructor; eauto.
    + by simplify_type_equality.
    + intuition.
  * intros ? τ'; intros; simplify_option_equality.
    typed_constructor; eauto using pbits_indetify_idempotent.
    + erewrite <-ctree_unflatten_type_of by eauto; eauto.
    + eauto using pbits_indetify_valid, ctree_flatten_valid.
    + erewrite fmap_length, drop_length,
        app_length, ctree_flatten_length by eauto; solve_length.
    + by intros [? _].
  * intros ? τ'; intros; simplify_option_equality. typed_constructor;
      eauto using pbits_indetify_valid, pbits_indetify_idempotent.
    + erewrite <-ctree_unflatten_type_of by eauto; eauto.
    + solve_length.
    + by intros [? _].
Qed.
Lemma ctree_alter_typed Γ Δ g w r τ w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' →
  (Γ,Δ) ⊢ g w' : type_of w' → ¬ctree_unmapped (g w') →
  (Γ,Δ) ⊢ ctree_alter Γ g r w : τ.
Proof.
  intros HΓ. revert g τ w. induction r as [|rs r IH] using @rev_ind.
  { by intros; simplify_type_equality'. }
  intros g τ w; rewrite ctree_alter_snoc, ctree_lookup_snoc; intros.
  destruct (w !!{Γ} rs) as [w''|] eqn:?; simplify_equality'.
  destruct (ctree_lookup_seg_Some Γ Δ w τ rs w'') as (?&_&?); eauto.
  eapply ctree_alter_seg_typed; eauto using
    ctree_lookup_seg_typed, ctree_alter_lookup_Forall, type_of_typed.
Qed.
Lemma ctree_alter_seg_type_of Γ g w rs :
  (∀ w', type_of (g w') = type_of w') →
  type_of (ctree_alter_seg Γ g rs w) = type_of w.
Proof.
  intros; destruct w as [|[]| | |], rs as [[]| |];
    simpl; unfold default; repeat (simplify_option_equality || case_match);
    f_equal'; rewrite ?alter_length; auto.
Qed.
Lemma ctree_alter_type_of Γ g w r :
  (∀ w', type_of (g w') = type_of w') →
  type_of (ctree_alter Γ g r w) = type_of w.
Proof. revert g w. induction r; simpl; auto using ctree_alter_seg_type_of. Qed.
Lemma ctree_alter_seg_type_of_weak Γ Δ g w rs τ w' :
  (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' →
  type_of (g w') = type_of w' → type_of (ctree_alter_seg Γ g rs w) = τ.
Proof.
  intros Hw Hrs. destruct rs as [[]| |], Hw as [|?? []| | |];
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs; intros;
    simplify_option_equality; simplify_type_equality; by rewrite ?alter_length.
Qed.
Lemma ctree_alter_type_of_weak Γ Δ g w r τ w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' →
  type_of (g w') = type_of w' → type_of (ctree_alter Γ g r w) = τ.
Proof.
  revert g τ w. induction r as [|rs r IH] using @rev_ind.
  { by intros; simplify_type_equality'. }
  intros g τ w; rewrite ctree_alter_snoc, ctree_lookup_snoc; intros.
  destruct (w !!{Γ} rs) as [w''|] eqn:?; simplify_equality'.
  destruct (ctree_lookup_seg_Some Γ Δ w τ rs w'') as (?&_&?); eauto.
  eapply ctree_alter_seg_type_of_weak; eauto using type_of_typed.
Qed.
Lemma ctree_lookup_alter_seg_freeze Γ g w rs w' :
  ✓ Γ → w !!{Γ} freeze false rs = Some w' →
  ctree_alter_seg Γ g rs w !!{Γ} freeze true rs = Some (g w').
Proof.
  destruct w, rs; intros; simplify_option_equality; try done.
  * rewrite list_lookup_alter. simplify_option_equality. done.
  * exfalso. eauto using alter_length.
  * rewrite list_lookup_alter. by simplify_option_equality.
Qed.
Lemma ctree_lookup_alter_freeze Γ g w r w' :
  ✓ Γ → w !!{Γ} (freeze false <$> r) = Some w' →
  ctree_alter Γ g r w !!{Γ} (freeze true <$> r) = Some (g w').
Proof.
  intros HΓ. revert g w. induction r as [|rs r IH] using rev_ind; simpl.
  { intros g w. rewrite !ctree_lookup_nil. congruence. }
  intros g w. rewrite !fmap_app, !fmap_cons, !fmap_nil, !ctree_alter_snoc,
    !ctree_lookup_snoc; intros; simplify_option_equality.
  erewrite ctree_lookup_alter_seg_freeze by eauto; eauto.
Qed.
Lemma ctree_lookup_alter Γ g w r1 r2 w' :
  ✓ Γ → w !!{Γ} (freeze false <$> r1) = Some w' →
  freeze true <$> r1 = freeze true <$> r2 →
  ctree_alter Γ g r2 w !!{Γ} r1 = Some (g w').
Proof.
  intros ?? Hr. apply ctree_lookup_le with (freeze true <$> r1);
    auto using ref_freeze_le_l; rewrite Hr.
  eapply ctree_lookup_alter_freeze;
    eauto using ctree_lookup_le, ref_freeze_le_r.
  by rewrite <-(ref_freeze_freeze _ true), <-Hr, ref_freeze_freeze.
Qed.
Lemma ctree_lookup_alter_seg_inv Γ Δ g w rs τ σ w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → Γ ⊢ rs : τ ↣ σ →
  ctree_alter_seg Γ g rs w !!{Γ} rs = Some w' →
  ∃ w'', w' = g w'' ∧ (Γ,Δ) ⊢ w'' : σ.
Proof.
  intros ? Hw. destruct 1 as [τ i|s i τs|s i q τs τ];
    pattern w; apply (ctree_typed_inv_r _ _ _ _ _ Hw); clear w Hw.
  * intros ws -> ?? Hw'.
    simplify_option_equality; rewrite list_lookup_alter in Hw'.
    destruct (ws !! i) as [w''|] eqn:?; simplify_equality'.
    exists w''; split; auto. eapply (Forall_lookup_1 (λ w', _ ⊢ w' : _)); eauto.
  * intros wxbss ?????? Hw'; simplify_equality'; case_option_guard; try done.
    rewrite list_lookup_alter in Hw'.
    destruct (wxbss !! i) as [[w'' xbs]|] eqn:?; simplify_equality'.
    exists w''; split; auto. by decompose_Forall_hyps.
  * intros; simplify_option_equality;
      eauto 8 using ctree_unflatten_typed, ctree_flatten_valid.
  * intros; simplify_option_equality; eauto 7 using ctree_unflatten_typed.
Qed.
Lemma ctree_lookup_alter_inv Γ Δ g w r τ σ w' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → Γ ⊢ r : τ ↣ σ →
  ctree_alter Γ g r w !!{Γ} r = Some w' →
  ∃ w'', w' = g w'' ∧ (Γ,Δ) ⊢ w'' : σ.
Proof.
  intros ? Hw Hr. revert g w w' Hw.
  induction Hr as [|r rs ????? IH] using @ref_typed_ind.
  { intros ? w ???; simplify_type_equality. by exists w. }
  intros g w w' Hw'. rewrite ctree_alter_cons, ctree_lookup_cons; intros.
  destruct (ctree_alter Γ (ctree_alter_seg Γ g rs) r w !!{Γ} r)
    as [w''|] eqn:Hw''; simplify_equality'.
  apply IH in Hw''; auto; destruct Hw'' as (w'''&->&?).
  eauto using ctree_lookup_alter_seg_inv.
Qed.
Lemma ctree_lookup_alter_seg_disjoint Γ g w rs1 rs2 :
  rs1 ⊥ rs2 → ctree_alter_seg Γ g rs2 w !!{Γ} rs1 = w !!{Γ} rs1.
Proof.
  destruct w; destruct 1; simpl; auto.
  * by rewrite alter_length, list_lookup_alter_ne by done.
  * by rewrite list_lookup_alter_ne by done.
Qed.
Lemma ctree_lookup_alter_disjoint Γ g w r1 r2 w' :
  ✓ Γ → r1 ⊥ r2 → w !!{Γ} r1 = Some w' →
  ctree_alter Γ g r2 w !!{Γ} r1 = Some w'.
Proof.
  intros HΓ. rewrite ref_disjoint_alt. intros (r1'&rs1&r&r2'&rs2&r'&->&->&?&Hr).
  rewrite !ctree_alter_app, !ctree_lookup_app, !ctree_alter_cons,
    !ctree_alter_nil, !ctree_lookup_cons, !ctree_lookup_nil; intros.
  destruct (w !!{_} r) as [w1'|] eqn:Hw1'; simplify_equality'.
  destruct (w1' !!{_} rs1) as [w2'|] eqn:Hw2'; simplify_equality'.
  erewrite ctree_lookup_alter by eauto using ctree_lookup_le, ref_freeze_le_r.
  by csimpl; rewrite ctree_lookup_alter_seg_disjoint, Hw2' by done.
Qed.
Lemma ctree_alter_seg_ext_lookup Γ g1 g2 w rs w' :
  w !!{Γ} rs = Some w' → g1 w' = g2 w' →
  ctree_alter_seg Γ g1 rs w = ctree_alter_seg Γ g2 rs w.
Proof.
  destruct w, rs; intros Hrs;
    pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs;
    intros; simplify_option_equality; f_equal; auto.
  * apply list_alter_ext; naive_solver.
  * apply list_alter_ext; auto 1. by intros [] ?; simplify_equality'; f_equal.
Qed.
Lemma ctree_alter_ext_lookup Γ g1 g2 w r w' :
  w !!{Γ} r = Some w' → g1 w' = g2 w' →
  ctree_alter Γ g1 r w = ctree_alter Γ g2 r w.
Proof.
  revert g1 g2 w'. induction r as [|rs r]; simpl; intros g1 g2 w'.
  { by intros; simplify_type_equality'. }
  rewrite ctree_lookup_cons; intros; simplify_option_equality;
    eauto using ctree_alter_seg_ext_lookup.
Qed.
Lemma ctree_alter_seg_perm_flatten Γ Δ g w τ rs w' τ' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} rs = Some w' → (Γ,Δ) ⊢ w' : τ' →
  tagged_perm <$> ctree_flatten (ctree_alter_seg Γ g rs w) = tagged_perm <$>
    take (ref_seg_object_offset Γ rs) (ctree_flatten w) ++
    ctree_flatten (g w') ++
    drop (ref_seg_object_offset Γ rs + bit_size_of Γ τ') (ctree_flatten w).
Proof.
  intros HΓ Hw Hrs Hw'. rewrite <-(type_of_correct (Γ,Δ) w' τ') by done.
  clear Hw'. revert w τ Hw Hrs. refine (ctree_typed_ind _ _ _ _ _ _ _ _).
  * by destruct rs.
  * intros ws τ Hws _ _ Hrs; destruct rs as [i| |]; pattern w';
      apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear w' Hrs; simpl.
    intros w'' <- ->. revert i w''.
    induction Hws as [|w ws ?? IH]; intros [|i] w'' ?;
      decompose_Forall_hyps; simplify_type_equality.
    { by rewrite drop_app_alt by done. }
    erewrite fmap_app, IH, !fmap_app by eauto; simplify_type_equality.
    rewrite take_plus_app, fmap_app, <-!(associative_L (++)) by done.
    by rewrite <-Nat.add_assoc, drop_plus_app by done.
  * intros s wxbss τs Hs Hws _ _ Hindet Hlen Hrs; destruct rs as [|i|];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    intros w xs -> Hi; destruct (Forall2_lookup_l (typed (Γ,Δ) ∘ fst)
      wxbss τs i (w,xs)) as (τ&Hi'&Hw); auto;
      simplify_option_equality; simplify_type_equality'.
    assert (field_bit_offset Γ τs i =
      length (take i wxbss ≫= λ wxs, ctree_flatten (wxs.1) ++ wxs.2)) as help2.
    { clear Hs Hi' Hw Hindet. apply lookup_lt_Some in Hi.
      unfold field_bit_padding, field_bit_offset in *.
      revert i wxbss Hi Hlen Hws. induction (bit_size_of_fields _ τs HΓ);
        intros [|?] ????; decompose_Forall_hyps;
        rewrite ?app_length; f_equal; auto; solve_length. }
    rewrite <-(take_drop_middle wxbss i (w,xs)), bind_app by done; csimpl.
    erewrite take_app_alt, drop_plus_app,
      <-(associative_L (++)), drop_app_alt, alter_app_r_alt by done.
    rewrite take_length_le by eauto using Nat.lt_le_incl, lookup_lt_Some.
    rewrite Nat.sub_diag; simpl; rewrite bind_app, bind_cons; simpl.
    by rewrite !(associative_L (++)).
  * intros s i τs w xs τ Hs Hτ ? _ _ Hindet ? _ Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    { intros -> ->; simplify_option_equality; simplify_type_equality.
      by rewrite drop_app_alt by done. }
    intros ? τ'' -> ? -> ?? _ _; simplify_option_equality.
    by rewrite ctree_unflatten_type_of, !fmap_app, <-list_fmap_compose by eauto.
  * intros s τs xs ? _ ? Hrs; destruct rs as [| |i'];
      pattern w'; apply (ctree_lookup_seg_inv _ _ _ _ _ Hrs); clear Hrs.
    intros ?? -> ?? _; simplify_option_equality.
    by rewrite ctree_unflatten_type_of, !fmap_app, <-list_fmap_compose by eauto.
Qed.
Lemma ctree_alter_perm_flatten Γ Δ g w τ r w' τ' :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} r = Some w' → (Γ,Δ) ⊢ w' : τ' →
  tagged_perm <$> ctree_flatten (ctree_alter Γ g r w) = tagged_perm <$>
    take (ref_object_offset Γ r) (ctree_flatten w) ++
    ctree_flatten (g w') ++
    drop (ref_object_offset Γ r + bit_size_of Γ τ') (ctree_flatten w).
Proof.
  intros HΓ ?. unfold ref_object_offset.
  revert g w' τ'. induction r as [|rs r IH]; intros g w'' τ''.
  { intros; simplify_type_equality'.
    by rewrite drop_ge, (right_id_L [] (++)) by auto. }
  rewrite ctree_lookup_cons; intros.
  destruct (w !!{Γ} r) as [w'|] eqn:?; simplify_equality'.
  destruct (ctree_lookup_Some Γ Δ w τ r w') as (τ'&?&?); auto.
  destruct (ctree_lookup_seg_Some Γ Δ w' τ' rs w'') as (?&?&?); auto.
  simplify_type_equality'.
  assert (ref_seg_object_offset Γ rs + bit_size_of Γ τ'' ≤ bit_size_of Γ τ')
    by eauto using ref_seg_object_offset_size'.
  erewrite !fmap_app, IH, !fmap_app, ctree_alter_seg_perm_flatten by eauto.
  rewrite !fmap_app, <-!(associative_L (++)), (associative_L (++)).
  repeat f_equal.
  { erewrite <-(ctree_lookup_flatten _ _ w _ _ w'), !fmap_take,
      pbits_perm_mask by eauto using ctree_lookup_typed.
    rewrite fmap_take, fmap_drop, take_take, Min.min_l by lia.
    by rewrite take_take_drop, Nat.add_comm. }
  erewrite <-(ctree_lookup_flatten _ _ w _ _ w'), !fmap_drop,
    pbits_perm_mask by eauto using ctree_lookup_typed; unfold ref_object_offset.
  rewrite fmap_take, fmap_drop, take_drop_commute, drop_drop.
  rewrite drop_take_drop by lia; f_equal; lia.
Qed.

(** ** Non-aliasing resuls *)
Lemma ctree_lookup_non_aliasing_help Γ Δ g w τ s τs r τ1 i1 τ2 i2 :
  let r1' := RUnion i1 s true :: r in
  let r2' := RUnion i2 s true :: r in
  ✓ Γ → (Γ,Δ) ⊢ w : τ → Γ ⊢ r : τ ↣ unionT s → Γ !! s = Some τs →
  τs !! i1 = Some τ1 → τs !! i2 = Some τ2 →
  i1 ≠ i2 → ctree_alter Γ g r1' w !!{Γ} r2' = None.
Proof.
  intros r1' r2' ? Hwτ Hw Hr ?? Hi. unfold r1', r2'; clear r1' r2'.
  rewrite !ctree_alter_cons, !ctree_lookup_cons.
  destruct (ctree_alter Γ (ctree_alter_seg Γ g
    (RUnion i1 s true)) r w !!{Γ} r) as [w'|] eqn:Hw'; simpl; [|done].
  eapply ctree_lookup_alter_inv in Hw'; eauto. destruct Hw' as (w''&->&?).
  by pattern w''; apply (ctree_typed_inv_r Γ Δ _ w'' (unionT s));
    intros; simplify_option_equality.
Qed.
Lemma ctree_lookup_non_aliasing Γ Δ g w τ s r r1 j1 σ1 i1 r2 j2 σ2 i2 :
  let r1' := r1 ++ RUnion i1 s true :: r in
  let r2' := r2 ++ RUnion i2 s true :: r in
  ✓ Γ → (Γ,Δ) ⊢ w : τ → Γ ⊢ r1' : τ ↣ σ1 → Γ ⊢ r2' : τ ↣ σ2 → i1 ≠ i2 →
  ctree_alter Γ g (ref_set_offset j1 r1') w
    !!{Γ} (ref_set_offset j2 r2') = None.
Proof.
  assert (∀ j r3 i3, ref_set_offset j (r3 ++ RUnion i3 s true :: r) =
    ref_set_offset j r3 ++ RUnion i3 s true :: r) as Hrhelp.
  { by intros ? [|??] ?. }
  intros r1' r2' HΓ; unfold r1', r2'; clear r1' r2'.
  rewrite !Hrhelp, !ref_typed_app; setoid_rewrite ref_typed_cons.
  intros Hwτ (τ1&(τ'&?&Hr1)&?) (τ2&(τ''&?&Hr2)&?) Hi; simplify_type_equality.
  inversion Hr1; inversion Hr2; simplify_option_equality.
  rewrite ctree_lookup_app, ctree_alter_app, bind_None; left.
  eauto using ctree_lookup_non_aliasing_help.
Qed.

(** ** Looking up individual bytes *)
Lemma ctree_lookup_byte_typed Γ Δ w τ i c :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} i = Some c → (Γ,Δ) ⊢ c : ucharT.
Proof.
  unfold lookupE, ctree_lookup_byte; intros; simplify_option_equality.
  apply ctree_unflatten_typed; eauto using TBase_valid, TInt_valid,
    Forall_sublist_lookup, ctree_flatten_valid.
Qed.
Lemma ctree_lookup_byte_length Γ Δ w τ i c :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} i = Some c → i < size_of Γ τ.
Proof.
  unfold lookupE, ctree_lookup_byte, sublist_lookup.
  intros; simplify_option_equality.
  apply (Nat.mul_lt_mono_pos_r (char_bits)); auto using char_bits_pos.
  change (size_of Γ τ * char_bits) with (bit_size_of Γ τ).
  erewrite <-ctree_flatten_length by eauto. pose proof char_bits_pos; lia.
Qed.
Lemma ctree_lookup_byte_Forall (P : pbit K → Prop) Γ w i c :
  ✓ Γ → (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → w !!{Γ} i = Some c → ctree_Forall P c.
Proof.
  unfold lookupE, ctree_lookup_byte; intros; simplify_option_equality.
  eauto using TBase_valid, TInt_valid, Forall_sublist_lookup.
Qed.
Lemma ctree_flatten_mask Γ Δ w τ :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → 
  mask pbit_indetify (type_mask Γ τ) (ctree_flatten w) = ctree_flatten w.
Proof.
  intros. rewrite <-ctree_flatten_union_reset at 2.
  by erewrite <-ctree_unflatten_flatten, ctree_flatten_unflatten by eauto.
Qed.
Definition ctree_lookup_byte_after (Γ : env K)
    (τ : type K) (i : nat) : mtree K → mtree K :=
  ctree_unflatten Γ ucharT ∘
    mask pbit_indetify (take char_bits (drop (i * char_bits) (type_mask Γ τ))) ∘
    ctree_flatten.
Lemma ctree_lookup_byte_after_spec Γ Δ w τ i :
  ✓Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} i = ctree_lookup_byte_after Γ τ i <$> w !!{Γ} i.
Proof.
  intros. unfold lookupE, ctree_lookup_byte, ctree_lookup_byte_after.
  destruct (sublist_lookup (i * char_bits) _ _) as [xbs|] eqn:?; f_equal'.
  unfold sublist_lookup in *; simplify_option_equality.
  by erewrite <-take_mask, <-drop_mask, ctree_flatten_mask by eauto.
Qed.
Lemma ctree_lookup_byte_after_Forall (P : pbit K → Prop) Γ τ i w :
  (∀ xb, P xb → P (pbit_indetify xb)) →
  ctree_Forall P w → ctree_Forall P (ctree_lookup_byte_after Γ τ i w).
Proof.
  intros ? Hw. unfold ctree_lookup_byte_after; simpl.
  generalize (take char_bits (drop (i * char_bits) (type_mask Γ τ))).
  induction Hw; intros [|[] ?]; simpl; auto.
Qed.
Lemma ctree_lookup_byte_ext Γ Δ w1 w2 τ :
  ✓ Γ → (Γ,Δ) ⊢ w1 : τ → union_free w1 → (Γ,Δ) ⊢ w2 : τ → union_free w2 →
  (∀ i, i < size_of Γ τ → w1 !!{Γ} i = w2 !!{Γ} i) → w1 = w2.
Proof.
  intros ????? Hlookup. erewrite <-(union_free_reset w1),
    <-(union_free_reset w2), <-!ctree_unflatten_flatten by eauto.
  f_equal; apply sublist_eq_same_length with (size_of Γ τ) char_bits.
  { by erewrite ctree_flatten_length by eauto. }
  { by erewrite ctree_flatten_length by eauto. }
  intros i Hi. specialize (Hlookup i Hi).
  unfold lookupE, ctree_lookup_byte in Hlookup.
  destruct (sublist_lookup _ _(ctree_flatten w1)) as [bs1|] eqn:?,
    (sublist_lookup _ _(ctree_flatten w2)) as [bs2|] eqn:?; try done.
  apply (injective Some) in Hlookup; rewrite !ctree_unflatten_base in Hlookup.
  congruence.
Qed.
Lemma ctree_lookup_byte_char Γ Δ w :
  ✓ Γ → (Γ,Δ) ⊢ w : ucharT → w !!{Γ} 0 = Some w.
Proof.
  intros ? Hw. unfold lookupE, ctree_lookup_byte; simpl.
  rewrite sublist_lookup_all by auto. f_equal'.
  erewrite ctree_unflatten_flatten by eauto. by inversion Hw.
Qed.
Lemma ctree_lookup_reshape Γ Δ w τ i :
  let szs := replicate (size_of Γ τ) char_bits in
  ✓ Γ → (Γ,Δ) ⊢ w : τ →
  w !!{Γ} i = ctree_unflatten Γ ucharT <$> reshape szs (ctree_flatten w) !! i.
Proof.
  intros szs ? Hwτ. unfold lookupE at 1, ctree_lookup_byte. unfold szs.
  by rewrite sublist_lookup_reshape
    by (erewrite ?ctree_flatten_length by eauto; eauto using char_bits_pos).
Qed.
Lemma ctree_lookup_byte_flatten Γ w i w' :
  w !!{Γ} i = Some w' →
  take (char_bits) (drop (i * char_bits) (ctree_flatten w)) = ctree_flatten w'.
Proof.
  unfold lookupE, ctree_lookup_byte, sublist_lookup; intros.
  by simplify_option_equality.
Qed.

(** ** Altering individual bytes *)
Lemma ctree_alter_byte_typed Γ Δ g w i c τ :
  ✓ Γ → w !!{Γ} i = Some c → (Γ,Δ) ⊢ w : τ →
  (Γ,Δ) ⊢ g c : ucharT → (Γ,Δ) ⊢ ctree_alter_byte Γ g i w : τ.
Proof.
  unfold lookupE, ctree_lookup_byte, ctree_alter_byte. intros ? Hw ??.
  destruct (sublist_lookup _ _ _) as [xbs|] eqn:?; simplify_type_equality'.
  set (G := ctree_flatten ∘ g ∘ ctree_unflatten Γ ucharT).
  assert (length (G xbs) = char_bits).
  { unfold G; simplify_option_equality; auto. }
  apply ctree_unflatten_typed; eauto 2.
  eapply Forall_sublist_alter; unfold G; simpl; eauto using ctree_flatten_valid.
Qed.
Lemma ctree_alter_byte_Forall (P : pbit K → Prop) Γ Δ g w i c τ :
  ✓ Γ → (∀ xb, P xb → P (pbit_indetify xb)) →
  w !!{Γ} i = Some c → (Γ,Δ) ⊢ w : τ → (Γ,Δ) ⊢ g c : ucharT →
  ctree_Forall P w → ctree_Forall P (g c) →
  ctree_Forall P (ctree_alter_byte Γ g i w).
Proof.
  unfold lookupE, ctree_lookup_byte, ctree_alter_byte. intros.
  destruct (sublist_lookup _ _ _) as [xbs|] eqn:?; simplify_type_equality'.
  set (G := ctree_flatten ∘ g ∘ ctree_unflatten Γ ucharT).
  assert (length (G xbs) = char_bits).
  { unfold G; simplify_option_equality; auto. }
  eapply ctree_unflatten_Forall; eauto 1 using ctree_typed_type_valid.
  eapply Forall_sublist_alter; unfold G; simpl; eauto.
Qed.
Lemma ctree_alter_byte_type_of Γ g i w :
  ✓ Γ → ✓{Γ} (type_of w) → type_of (ctree_alter_byte Γ g i w) = type_of w.
Proof. apply ctree_unflatten_type_of. Qed.
Lemma ctree_alter_byte_union_free Γ g w i :
  ✓ Γ → ✓{Γ} (type_of w) → union_free (ctree_alter_byte Γ g i w).
Proof. apply ctree_unflatten_union_free. Qed.
Lemma ctree_alter_byte_char Γ Δ g w :
  ✓ Γ → (Γ,Δ) ⊢ w : ucharT → (Γ,Δ) ⊢ g w : ucharT →
  ctree_alter_byte Γ g 0 w = g w.
Proof.
  intros ?? Hc. unfold ctree_alter_byte; simplify_type_equality'.
  erewrite sublist_alter_all by auto; simpl.
  by erewrite (ctree_unflatten_flatten _ _ w), union_free_reset,
    ctree_unflatten_flatten, union_free_reset by eauto using union_free_base.
Qed.
Lemma ctree_lookup_alter_byte Γ Δ g w τ i c :
  ✓ Γ → w !!{Γ} i = Some c → (Γ,Δ) ⊢ g c : ucharT → (Γ,Δ) ⊢ w : τ → 
  ctree_alter_byte Γ g i w !!{Γ} i
  = ctree_lookup_byte_after Γ τ i <$> g <$> w !!{Γ} i.
Proof.
  unfold lookupE, ctree_lookup_byte, ctree_alter_byte. intros.
  destruct (sublist_lookup _ _ (ctree_flatten w))
    as [xbs|] eqn:?; simplify_type_equality'.
  set (G:=ctree_flatten ∘ g ∘ ctree_unflatten Γ ucharT).
  assert (length (G xbs) = char_bits).
  { unfold G; simplify_option_equality; auto. }
  erewrite ctree_flatten_unflatten
    by (rewrite ?sublist_alter_length by auto; eauto).
  erewrite sublist_lookup_mask, sublist_lookup_alter by eauto.
  unfold G, ctree_lookup_byte_after. by simplify_option_equality.
Qed.
Lemma ctree_lookup_alter_byte_ne Γ Δ g w τ i j c :
  ✓ Γ → w !!{Γ} j = Some c → (Γ,Δ) ⊢ g c : ucharT →
  (Γ,Δ) ⊢ w : τ → i ≠ j → ctree_alter_byte Γ g j w !!{Γ} i = w !!{Γ} i.
Proof.
  unfold lookupE, ctree_lookup_byte, ctree_alter_byte. intros.
  destruct (sublist_lookup (j * _) _ (ctree_flatten w))
    as [xbs|] eqn:?; simplify_type_equality'.
  set (G:=ctree_flatten ∘ g ∘ ctree_unflatten Γ ucharT).
  assert (length (G xbs) = char_bits).
  { unfold G; simplify_option_equality; auto. }
  assert (i * char_bits + char_bits ≤ j * char_bits
    ∨ j * char_bits + char_bits ≤ i * char_bits).
  { destruct (decide (i < j)); [left|right];
      rewrite <-Nat.mul_succ_l; apply Nat.mul_le_mono_r; lia. }
  erewrite ctree_flatten_unflatten, sublist_lookup_mask,
    sublist_lookup_alter_ne by eauto.
  destruct (sublist_lookup (i * char_bits) _ _) as [xbs'|] eqn:?; f_equal'.
  unfold sublist_lookup in *; simplify_option_equality.
  by erewrite <-take_mask, <-drop_mask, ctree_flatten_mask by eauto.
Qed.
Lemma ctree_alter_byte_commute Γ Δ g1 g2 w τ i j c1 c2 :
  ✓ Γ → w !!{Γ} i = Some c1 → (Γ,Δ) ⊢ g1 c1 : ucharT →
  w !!{Γ} j = Some c2 → (Γ,Δ) ⊢ g2 c2 : ucharT → (Γ,Δ) ⊢ w : τ → i ≠ j →
  ctree_alter_byte Γ g1 i (ctree_alter_byte Γ g2 j w)
  = ctree_alter_byte Γ g2 j (ctree_alter_byte Γ g1 i w).
Proof.
  intros. assert (ctree_alter_byte Γ g2 j w !!{Γ} i = Some c1).
  { by erewrite ctree_lookup_alter_byte_ne by eauto. }
  assert (ctree_alter_byte Γ g1 i w !!{Γ} j = Some c2).
  { by erewrite ctree_lookup_alter_byte_ne by eauto. }
  assert (✓{Γ} (type_of (ctree_alter_byte Γ g1 i w))).
  { rewrite ctree_alter_byte_type_of; simplify_type_equality; eauto. }
  assert (✓{Γ} (type_of (ctree_alter_byte Γ g2 j w))).
  { rewrite ctree_alter_byte_type_of; simplify_type_equality; eauto. }
  eapply ctree_lookup_byte_ext;
    eauto using ctree_alter_byte_union_free, ctree_alter_byte_typed.
  intros ii _. destruct (decide (ii = i)) as [->|].
  { by erewrite ctree_lookup_alter_byte, ctree_lookup_alter_byte_ne,
      ctree_lookup_alter_byte_ne, ctree_lookup_alter_byte
      by eauto using ctree_alter_byte_typed. }
  destruct (decide (ii = j)) as [->|].
  { by erewrite ctree_lookup_alter_byte, ctree_lookup_alter_byte_ne,
      ctree_lookup_alter_byte, ctree_lookup_alter_byte_ne
      by eauto using ctree_alter_byte_typed. }
  by erewrite !ctree_lookup_alter_byte_ne by eauto using ctree_alter_byte_typed.
Qed.
Lemma ctree_alter_byte_unmapped Γ Δ g w i τ c :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → ctree_unmapped (ctree_alter_byte Γ g i w) →
  w !!{Γ} i = Some c → (Γ,Δ) ⊢ g c : ucharT → ctree_unmapped (g c).
Proof.
  unfold lookupE,ctree_lookup_byte,ctree_alter_byte. intros ?? Hw ??; revert Hw.
  destruct (sublist_lookup _ _ _) as [xbs|] eqn:?; simplify_type_equality'.
  rewrite ctree_flatten_unflatten
    by (unfold compose; eauto 1 using ctree_typed_type_valid); intros Hw.
  eapply (Forall_sublist_alter_inv _ (ctree_flatten ∘ g ∘ _)),
    pbits_unmapped_indetify_inv; eauto.
  eapply Forall_impl with ✓{Γ,Δ}; eauto using pbit_valid_sep_valid.
  eapply Forall_sublist_alter; simpl; eauto 2 using ctree_flatten_valid.
Qed.
Lemma ctree_alter_byte_perm_flatten Γ Δ g w τ i c :
  ✓ Γ → (Γ,Δ) ⊢ w : τ → w !!{Γ} i = Some c → (Γ,Δ) ⊢ g c : ucharT →
  tagged_perm <$> ctree_flatten (ctree_alter_byte Γ g i w) = tagged_perm <$>
    take (i * char_bits) (ctree_flatten w) ++
    ctree_flatten (g c) ++
    drop (char_bits + i * char_bits) (ctree_flatten w).
Proof.
  unfold lookupE, ctree_lookup_byte, ctree_alter_byte,
    sublist_alter, sublist_lookup; intros; simplify_type_equality'.
  case_option_guard as Hlen; simplify_equality'.
  erewrite ctree_flatten_length in Hlen by eauto.
  by rewrite ctree_flatten_unflatten, pbits_perm_mask, Nat.add_comm by eauto.
Qed.

(** * Properties of [ctree_singleton] *)
Lemma ctree_singleton_seg_le Γ rs1 rs2 w :
  rs1 ⊆ rs2 → ctree_singleton_seg Γ rs1 w = ctree_singleton_seg Γ rs2 w.
Proof. by destruct 1. Qed.
Lemma ctree_singleton_le Γ r1 r2 w :
  r1 ⊆* r2 → ctree_singleton Γ r1 w = ctree_singleton Γ r2 w.
Proof.
  intros Hr. revert w. induction Hr; intros w; simpl; auto.
  erewrite ctree_singleton_seg_le by eauto; eauto.
Qed.
Lemma ctree_singleton_seg_flatten Γ τ rs w σ :
  ✓ Γ → Γ ⊢ rs : τ ↣ σ → ✓{Γ} τ →
  ctree_flatten (ctree_singleton_seg Γ rs w) =
   replicate (ref_seg_object_offset Γ rs) ∅ ++
   ctree_flatten w ++
   replicate (bit_size_of Γ τ - ref_seg_object_offset Γ rs - bit_size_of Γ σ) ∅.
Proof.
  intros HΓ. destruct 1 as [τ i n Hi|s i τs τ Hs Hi|s i ? τs];
    intros Hτ; simplify_option_equality.
  * pattern n at 1; replace n with (i + S (n - i - 1)) by lia.
    rewrite replicate_plus; simpl.
    rewrite insert_app_r_alt, replicate_length, Nat.sub_diag by auto; simpl.
    rewrite bind_app, bind_cons, !ctree_flatten_replicate_new by eauto.
    by rewrite bit_size_of_array, !Nat.mul_sub_distr_r, Nat.mul_1_l.
  * erewrite bit_size_of_struct by eauto.
    assert (✓{Γ}* τs) by eauto; clear Hs Hτ; revert i Hi.
    unfold field_bit_offset, field_bit_padding.
    induction (bit_size_of_fields _ τs HΓ) as [|τ' sz τs szs ? Hszs IH];
      intros [|i] Hi; decompose_Forall_hyps.
    { rewrite Nat.sub_0_r, Nat.add_sub_swap, replicate_plus by done.
      rewrite !(associative_L (++)); f_equal. clear IH.
      induction Hszs as [|τ' sz' τs szs ?? IH]; decompose_Forall_hyps; auto.
      rewrite ctree_flatten_new, IH, <-!replicate_plus by done; f_equal; lia. }
    rewrite IH, ctree_flatten_new, (associative_L (++)),
      <-!replicate_plus by done; do 2 f_equal; auto with f_equal lia.
  * by rewrite Nat.sub_0_r.
Qed.
Lemma ctree_singleton_flatten Γ τ r w σ :
  ✓ Γ → Γ ⊢ r : τ ↣ σ → ✓{Γ} τ →
  ctree_flatten (ctree_singleton Γ r w) =
   replicate (ref_object_offset Γ r) ∅ ++
   ctree_flatten w ++
   replicate (bit_size_of Γ τ - ref_object_offset Γ r - bit_size_of Γ σ) ∅.
Proof.
  unfold ref_object_offset. intros ? Hrs; revert w.
  induction Hrs as [|r rs τ1 τ2 τ3 Hrs Hr IH]
    using @ref_typed_ind; intros w ?; csimpl.
  { by rewrite Nat.sub_0_r, Nat.sub_diag; simpl; rewrite (right_id_L [] (++)). }
  erewrite IH, ctree_singleton_seg_flatten
    by eauto using ref_typed_type_valid; clear IH.
  apply ref_seg_object_offset_size' in Hrs; auto.
  apply ref_object_offset_size' in Hr; auto; unfold ref_object_offset in Hr.
  rewrite !(associative_L (++)), <-replicate_plus,
    <-!(associative_L (++)), <-replicate_plus; f_lia.
Qed.
Lemma ctree_singleton_seg_Forall_inv P Γ τ rs w σ :
  ✓ Γ → Γ ⊢ rs : τ ↣ σ →
  ctree_Forall P (ctree_singleton_seg Γ rs w) → ctree_Forall P w.
Proof.
  destruct 2 as [τ i n|s i τs τ ? Hi|]; simplify_option_equality.
  * rewrite Forall_bind, Forall_lookup; intros Hw; apply (Hw i).
    by rewrite list_lookup_insert by auto.
  * rewrite Forall_bind, Forall_lookup; intros Hw; apply lookup_lt_Some in Hi.
    destruct (lookup_lt_is_Some_2 (field_bit_padding Γ τs) i) as [sz Hsz].
    { by rewrite field_bit_padding_length. }
    eapply (Forall_app _ _ (replicate _ _)), (Hw i (w,replicate sz ∅)).
    by rewrite lookup_zip_with,
      list_lookup_insert, list_lookup_fmap, Hsz by auto.
  * rewrite Forall_app; by intros [].
Qed.
Lemma ctree_singleton_Forall_inv P Γ τ r w σ :
  ✓ Γ → Γ ⊢ r : τ ↣ σ →
  ctree_Forall P (ctree_singleton Γ r w) → ctree_Forall P w.
Proof.
  intros ? Hr. revert w. induction Hr using @ref_typed_ind; simpl;
    eauto using ctree_singleton_seg_Forall_inv.
Qed.
Lemma ctree_singleton_seg_typed Γ Δ τ rs w σ :
  ✓ Γ → Γ ⊢ rs : τ ↣ σ → (Γ,Δ) ⊢ w : σ → ¬ctree_unmapped w →
  (Γ,Δ) ⊢ ctree_singleton_seg Γ rs w : τ.
Proof.
  destruct 2 as [τ i n|s i τs|s i ? τs]; intros; simpl.
  * typed_constructor; auto with lia. rewrite list_insert_alter.
    apply Forall_alter; eauto using ctree_new_typed.
  * assert (length (field_bit_padding Γ τs) = length τs) as Hlen
      by eauto using field_bit_padding_length.
    simplify_option_equality; typed_constructor; eauto.
    + rewrite <-Forall2_fmap_l, fst_zip, list_insert_alter by done.
      apply Forall2_alter_l; [|naive_solver].
      eapply Forall2_fmap_l, Forall2_Forall,
        Forall_impl; eauto using ctree_new_typed.
    + rewrite <-Forall_fmap, snd_zip by done.
      elim (field_bit_padding Γ τs); constructor; auto.
      apply Forall_replicate; auto.
    + generalize (<[i:=w]> (ctree_new Γ ∅ <$> τs)); clear Hlen.
      by induction (field_bit_padding Γ τs); intros [|??];
        constructor; csimpl; rewrite ?fmap_replicate.
    + rewrite list_fmap_compose, snd_zip by done.
      by induction (field_bit_padding Γ τs) in |- *; f_equal'.
  * simplify_option_equality; typed_constructor; eauto.
    + by induction (_ - _); f_equal'.
    + solve_length.
    + naive_solver.
Qed.
Lemma ctree_singleton_typed Γ Δ τ r σ w :
  ✓ Γ → Γ ⊢ r : τ ↣ σ → (Γ,Δ) ⊢ w : σ → ¬ctree_unmapped w →
  (Γ,Δ) ⊢ ctree_singleton Γ r w : τ.
Proof.
  intros ? Hr. revert w. induction Hr using @ref_typed_ind; eauto 10 using
    ctree_singleton_seg_typed, ctree_singleton_seg_Forall_inv.
Qed.
Lemma ctree_singleton_seg_weaken Γ1 Γ2 τ rs w σ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → Γ1 ⊢ rs : τ ↣ σ → ✓{Γ1} τ → 
  ctree_singleton_seg Γ1 rs w = ctree_singleton_seg Γ2 rs w.
Proof.
  by destruct 3; intros;
    simplify_option_equality by eauto using lookup_compound_weaken;
    erewrite ?ctree_new_weaken, ?ctree_news_weaken,
    ?field_bit_padding_weaken, ?(bit_size_of_weaken Γ1 Γ2) by eauto.
Qed.
Lemma ctree_singleton_weaken Γ1 Γ2 τ r w σ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → Γ1 ⊢ r : τ ↣ σ → ✓{Γ1} τ →
  ctree_singleton Γ1 r w = ctree_singleton Γ2 r w.
Proof.
  intros ?? Hr. revert w. induction Hr using @ref_typed_ind; intros; simpl;
    erewrite ?ctree_singleton_seg_weaken by eauto using ref_typed_type_valid;
    eauto.
Qed.
Lemma ctree_lookup_singleton_seg Γ τ rs w σ :
  ✓ Γ → Γ ⊢ rs : τ ↣ σ → ctree_singleton_seg Γ rs w !!{Γ} rs = Some w.
Proof.
  destruct 2 as [|s i τs|]; simplify_option_equality.
  * by rewrite list_lookup_insert by solve_length.
  * assert (length (field_bit_padding Γ τs) = length τs) as Hlen
      by eauto using field_bit_padding_length.
    assert (i < length τs) by eauto using lookup_lt_Some.
    by rewrite <-list_lookup_fmap, fst_zip, list_lookup_insert by solve_length.
  * done.
Qed.
Lemma ctree_lookup_singleton Γ τ r w σ :
  ✓ Γ → Γ ⊢ r : τ ↣ σ → ctree_singleton Γ r w !!{Γ} r = Some w.
Proof.
  intros ? Hr. revert w. induction Hr as [|r rs τ1 τ2 τ3 ?? IH]
    using @ref_typed_ind; intros; simpl; auto.
  rewrite ctree_lookup_cons, IH; f_equal';
    eauto using ctree_lookup_singleton_seg.
Qed.
Lemma ctree_alter_singleton_seg Γ g τ rs w σ :
  Γ ⊢ rs : τ ↣ σ →
  ctree_alter_seg Γ g rs (ctree_singleton_seg Γ rs w)
  = ctree_singleton_seg Γ rs (g w).
Proof.
  destruct 1; simplify_option_equality; f_equal.
  { by rewrite !list_insert_alter, <-list_alter_compose. }
  rewrite !list_insert_alter. generalize i (ctree_new Γ ∅ <$> τs).
  induction (_ <$> _); intros [|?] [|??]; f_equal'; auto.
Qed.
Lemma ctree_alter_singleton Γ g τ r w σ :
  Γ ⊢ r : τ ↣ σ →
  ctree_alter Γ g r (ctree_singleton Γ r w) = ctree_singleton Γ r (g w).
Proof.
  intros Hr. revert g w. induction Hr as [|r rs τ1 τ2 τ3 ?? IH]
    using @ref_typed_ind; intros; simpl; auto.
  by erewrite IH, ctree_alter_singleton_seg by eauto.
Qed.
Lemma ctree_merge_new {B : Set} Γ f τ (ys : list B) xb :
  (∀ y, f xb y = xb) → pbit_indetify xb = xb →
  ✓ Γ → ✓{Γ} τ → length ys = bit_size_of Γ τ →
  ctree_merge true f (ctree_new Γ xb τ) ys = ctree_new Γ xb τ.
Proof.
  intros ???? Hlen; unfold ctree_new.
  assert (zip_with f (pbit_indetify <$> replicate (bit_size_of Γ τ) xb) ys
    = pbit_indetify <$> zip_with f (replicate (bit_size_of Γ τ) xb) ys).
  { rewrite fmap_replicate, !zip_with_replicate_l, <-list_fmap_compose by done.
    apply list_fmap_ext; simpl; intros; congruence. }
  by erewrite ctree_merge_unflatten,
    zip_with_replicate_l, const_fmap, Hlen by eauto.
Qed.
Lemma ctree_merge_singleton_seg {B : Set} Γ Δ f τ rs w (ys : list B) σ :
  (∀ y, f ∅ y = ∅) →
  ✓ Γ → Γ ⊢ rs : τ ↣ σ → (Γ,Δ) ⊢ w : σ → length ys = bit_size_of Γ τ →
  ctree_merge true f (ctree_singleton_seg Γ rs w) ys =
  ctree_singleton_seg Γ rs (ctree_merge true f w
    (take (bit_size_of Γ σ) (drop (ref_seg_object_offset Γ rs) ys))).
Proof.
  intros ? HΓ. destruct 1 as [τ i n _|s i τs τ Hs Hi|s i ? τs];
    intros Hw Hys; simplify_option_equality; f_equal.
  * revert i ys Hys. rewrite bit_size_of_array.
    induction n; intros [|?] ??; f_equal';
      erewrite <-?drop_drop, ?ctree_flatten_length, ?ctree_merge_new
      by eauto using (ctree_new_typed _ Δ); eauto.
    cut (length (drop (bit_size_of Γ τ) ys) = n * bit_size_of Γ τ); [|auto].
    generalize (drop (bit_size_of Γ τ) ys).
    elim n; intros; f_equal'; erewrite ?ctree_flatten_length,
      ?ctree_merge_new by eauto using (ctree_new_typed _ Δ); eauto.
  * revert i ys Hi Hys. erewrite bit_size_of_struct by eauto.
    assert (✓{Γ}* τs) by eauto. clear Hs.
    unfold field_bit_sizes,field_bit_offset, field_bit_padding, field_bit_sizes.
    induction (size_of_fields _ τs HΓ) as [|τ' sz τs szs ? Hszs IH];
      intros [|i] ys Hi Hlen; decompose_Forall_hyps.
    + erewrite ctree_flatten_length, replicate_length, drop_0,
        zip_with_replicate_l, const_fmap, take_length_le by eauto; f_equal.
      assert (bit_size_of Γ τ ≤ sz * char_bits).
      { by apply Nat.mul_le_mono_r. }
      rewrite drop_drop, le_plus_minus_r by done.
      cut (length (drop (sz * char_bits) ys)
        = sum_list ((λ sz, sz * char_bits) <$> szs)); [|solve_length].
      generalize (drop (sz * char_bits) ys); clear IH Hlen.
      induction Hszs as [|τ' sz' ???? IH];
        decompose_Forall_hyps; intros ys' ?; auto.
      assert (bit_size_of Γ τ' ≤ sz' * char_bits).
      { by apply Nat.mul_le_mono_r. }
      by erewrite ctree_flatten_length, IH, zip_with_replicate_l,
         const_fmap,replicate_length, take_length_le, ctree_merge_new
        by eauto using (ctree_new_typed _ Δ).
    + assert (bit_size_of Γ τ' ≤ sz * char_bits)
        by (by apply Nat.mul_le_mono_r).
      erewrite ctree_flatten_length, ctree_merge_new, replicate_length,
        zip_with_replicate_l, const_fmap, take_length_le, IH, !drop_drop
        by eauto using (ctree_new_typed _ Δ); f_lia.
  * by erewrite ctree_flatten_length by eauto.
  * erewrite ctree_flatten_length, zip_with_replicate_l by eauto.
    erewrite const_fmap by done; f_equal; auto.
Qed.
Lemma ctree_merge_singleton {B : Set} Γ Δ f τ r w (ys : list B) σ :
  (∀ y, f ∅ y = ∅) →
  ✓ Γ → Γ ⊢ r : τ ↣ σ → (Γ,Δ) ⊢ w : σ → ¬ctree_unmapped w →
  length ys = bit_size_of Γ τ →
  ctree_merge true f (ctree_singleton Γ r w) ys =
  ctree_singleton Γ r (ctree_merge true f w
    (take (bit_size_of Γ σ) (drop (ref_object_offset Γ r) ys))).
Proof.
  unfold ref_object_offset. intros ?? Hr. revert w ys.
  induction Hr as [|r rs τ1 τ2 τ3 Hrs Hr IH] using @ref_typed_ind;
    intros w ys ???; simplify_equality'; [by rewrite drop_0, take_ge by done|].
  apply ref_object_offset_size' in Hr; auto; unfold ref_object_offset in Hr.
  assert (ref_seg_object_offset Γ rs + bit_size_of Γ τ3 ≤ bit_size_of Γ τ2)
    by auto using  ref_seg_object_offset_size'.
  erewrite IH, ctree_merge_singleton_seg
    by eauto using ctree_singleton_seg_Forall_inv, ctree_singleton_seg_typed.
  rewrite !take_drop_commute,
    drop_drop, take_take, Min.min_l by solve_length; f_lia.
Qed.
End memory_trees.
