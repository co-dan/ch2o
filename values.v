(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export base_values memory_trees.
Local Open Scope ctype_scope.

Inductive val (Ti : Set) : Set :=
  | VBase : base_val Ti → val Ti
  | VArray : type Ti → list (val Ti) → val Ti
  | VStruct : tag → list (val Ti) → val Ti
  | VUnion : tag → nat → val Ti → val Ti
  | VUnionAll : tag → list (val Ti) → val Ti.

Delimit Scope base_val with V.
Bind Scope val_scope with val.
Open Scope val_scope.
Arguments VVoid {_}.
Arguments VBase {_} _.
Arguments VArray {_} _ _%V.
Arguments VStruct {_} _ _%V.
Arguments VUnion {_} _ _ _%V.
Arguments VUnionAll  {_} _ _%V.

Notation "'voidV'" := (VBase voidV) : val_scope.
Notation "'indetV' τ" := (VBase (indetV τ)) (at level 10) : val_scope.
Notation "'intV{' τi } x" := (VBase (intV{τi} x))
  (at level 10, format "intV{ τi }  x") : val_scope.
Notation "'ptrV' p" := (VBase (ptrV p)) (at level 10) : val_scope.
Notation "'byteV' bs" := (VBase (byteV bs)) (at level 10) : val_scope.

Instance: Injective (=) (=) (@VBase Ti).
Proof. by injection 1. Qed.
Instance: Injective2 (=) (=) (=) (@VArray Ti).
Proof. by injection 1. Qed.
Instance: Injective (=) (=) (@VStruct Ti s).
Proof. by injection 1. Qed.
Instance: Injective2 (=) (=) (=) (@VUnion Ti s).
Proof. by injection 1. Qed.
Instance: Injective (=) (=) (@VUnionAll Ti s).
Proof. by injection 1. Qed.

Instance maybe_VBase {Ti} : Maybe (@VBase Ti) := λ v,
  match v with VBase vb => Some vb | _ => None end.
Instance val_eq_dec {Ti : Set} `{∀ k1 k2 : Ti, Decision (k1 = k2)} :
  ∀ v1 v2 : val Ti, Decision (v1 = v2).
Proof.
 refine (
  fix go v1 v2 : Decision (v1 = v2) :=
  match v1, v2 with
  | VBase vb1, VBase vb2 => cast_if (decide_rel (=) vb1 vb2)
  | VArray τ1 vs1, VArray τ2 vs2 =>
     cast_if_and (decide_rel (=) τ1 τ2) (decide_rel (=) vs1 vs2)
  | VStruct s1 vs1, VStruct s2 vs2 =>
     cast_if_and (decide_rel (=) s1 s2) (decide_rel (=) vs1 vs2)
  | VUnion s1 i1 v1, VUnion s2 i2 v2 =>
     cast_if_and3 (decide_rel (=) s1 s2) (decide_rel (=) i1 i2)
       (decide_rel (=) v1 v2)
  | VUnionAll s1 vs1, VUnionAll s2 vs2 =>
     cast_if_and (decide_rel (=) s1 s2) (decide_rel (=) vs1 vs2)
  | _, _ => right _
  end); clear go; abstract congruence.
Defined.

Section val_ind.
  Context {Ti} (P : val Ti → Prop).
  Context (Pbase : ∀ vb, P (VBase vb)).
  Context (Parray : ∀ τ vs, Forall P vs → P (VArray τ vs)).
  Context (Pstruct : ∀ s vs, Forall P vs → P (VStruct s vs)).
  Context (Punion : ∀ s i v, P v → P (VUnion s i v)).
  Context (Punion_all : ∀ s vs, Forall P vs → P (VUnionAll s vs)).
  Definition val_ind_alt: ∀ v, P v :=
    fix go v :=
    match v return P v with
    | VBase _ => Pbase _
    | VArray _ _ => Parray _ _ $ list_ind (Forall _)
       (Forall_nil_2 _) (λ v _, Forall_cons_2 _ _ _ (go v)) _
    | VStruct _ _ => Pstruct _ _ $ list_ind (Forall _)
       (Forall_nil_2 _) (λ v _, Forall_cons_2 _ _ _ (go v)) _
    | VUnion _ _ _ => Punion _ _ _ (go _)
    | VUnionAll _ _ => Punion_all _ _ $ list_ind (Forall _)
       (Forall_nil_2 _) (λ v _, Forall_cons_2 _ _ _ (go v)) _
    end.
End val_ind.

Definition val_map {Ti} (f : base_val Ti → base_val Ti) : val Ti → val Ti :=
  fix go v :=
  match v with
  | VBase vb => VBase (f vb)
  | VArray τ vs => VArray τ (go <$> vs)
  | VStruct s vs => VStruct s (go <$> vs)
  | VUnion s i v => VUnion s i (go v)
  | VUnionAll s vs => VUnionAll s (go <$> vs)
  end.
Notation val_freeze β := (val_map (freeze β)).

Section operations.
  Context `{Env Ti}.

  Definition val_unflatten (Γ : env Ti) : type Ti → list (bit Ti) → val Ti :=
    type_iter
    (**i TBase =>     *) (λ τb bs, VBase (base_val_unflatten Γ τb bs))
    (**i TArray =>    *) (λ τ n rec bs, VArray τ (array_unflatten Γ rec τ n bs))
    (**i TCompound => *) (λ c s τs rec bs,
      match c with
      | Struct_kind => VStruct s (struct_unflatten Γ (λ τ bs,
         let τsz := bit_size_of Γ τ in rec τ (take τsz bs)) τs bs)
      | Union_kind =>
         VUnionAll s ((λ τ, rec τ (take (bit_size_of Γ τ) bs)) <$> τs)
      end) Γ.

  Inductive vals_representable (Γ : env Ti) (Γm : memenv Ti)
      (vs : list (val Ti)) (τs : list (type Ti)) : Prop :=
    make_vals_representable bs :
      ✓{Γ,Γm}* bs →
      Forall (λ τ, bit_size_of Γ τ ≤ length bs) τs →
      vs = (λ τ, val_unflatten Γ τ (take (bit_size_of Γ τ) bs)) <$> τs →
      vals_representable Γ Γm vs τs.
  Inductive val_typed' (Γ : env Ti) (Γm: memenv Ti) : val Ti → type Ti → Prop :=
    | VBase_typed vb τb :
       (Γ,Γm) ⊢ vb : τb → val_typed' Γ Γm (VBase vb) (baseT τb)
    | VArray_typed vs τ n :
       n = length vs → Forall (λ v, val_typed' Γ Γm v τ) vs → n ≠ 0 →
       val_typed' Γ Γm (VArray τ vs) (τ.[n])
    | VStruct_typed s vs τs :
       Γ !! s = Some τs → Forall2 (val_typed' Γ Γm) vs τs →
       val_typed' Γ Γm (VStruct s vs) (structT s)
    | VUnion_typed s i τs v τ :
       Γ !! s = Some τs → τs !! i = Some τ →
       val_typed' Γ Γm v τ → val_typed' Γ Γm (VUnion s i v) (unionT s)
    | VUnionAll_typed s vs τs :
       Γ !! s = Some τs → Forall2 (val_typed' Γ Γm) vs τs →
       vals_representable Γ Γm vs τs →
       val_typed' Γ Γm (VUnionAll s vs) (unionT s).
  Global Instance val_typed:
    Typed (env Ti * memenv Ti) (type Ti) (val Ti) := curry val_typed'.

  Lemma val_typed_inv_l Γ Γm (P : type Ti → Prop) v τ :
    (Γ,Γm) ⊢ v : τ →
    match v with
    | VBase vb => (∀ τb, (Γ,Γm) ⊢ vb : τb → P (baseT τb)) → P τ
    | VArray τ' vs =>
       (∀ n, n = length vs → (Γ,Γm) ⊢* vs : τ' → n ≠ 0 → P (τ'.[n])) → P τ
    | VStruct s vs =>
       (∀ τs, Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs → P (structT s)) → P τ
    | VUnion s i v =>
       (∀ τs τ', Γ !! s = Some τs → τs !! i = Some τ' →
         (Γ,Γm) ⊢ v : τ' → P (unionT s)) → P τ
    | VUnionAll s vs =>
       (∀ τs, Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs →
         vals_representable Γ Γm vs τs → P (unionT s)) → P τ
    end.
  Proof. destruct 1; simplify_equality; eauto. Qed.
  Lemma val_typed_inv_r Γ Γm (P : val Ti → Prop) v τ :
    (Γ,Γm) ⊢ v : τ →
    match τ with
    | baseT τb => (∀ vb, (Γ,Γm) ⊢ vb : τb → P (VBase vb)) → P v
    | τ'.[n] =>
       (∀ vs,
         n = length vs → (Γ,Γm) ⊢* vs : τ' → n ≠ 0 → P (VArray τ' vs)) → P v
    | structT s =>
       (∀ vs τs, Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs →
         P (VStruct s vs)) → P v
    | unionT s =>
       (∀ i τs v' τ', Γ !! s = Some τs → τs !! i = Some τ' →
         (Γ,Γm) ⊢ v' : τ' → P (VUnion s i v')) →
       (∀ vs τs, Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs →
         vals_representable Γ Γm vs τs → P (VUnionAll s vs)) → P v
    end.
  Proof. destruct 1; simplify_equality; eauto. Qed.
  Section val_typed_ind.
    Context (Γ : env Ti) (Γm : memenv Ti) (P : val Ti → type Ti → Prop).
    Context (Pbase : ∀ vb τb, (Γ,Γm) ⊢ vb : τb → P (VBase vb) (baseT τb)).
    Context (Parray : ∀ vs τ,
      (Γ,Γm) ⊢* vs : τ → Forall (λ v, P v τ) vs →
      length vs ≠ 0 → P (VArray τ vs) (τ.[length vs])).
    Context (Pstruct : ∀ s vs τs,
      Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs → Forall2 P vs τs →
      P (VStruct s vs) (structT s)).
    Context (PUnion : ∀ s i τs v τ,
      Γ !! s = Some τs → τs !! i = Some τ → (Γ,Γm) ⊢ v : τ → P v τ →
      P (VUnion s i v) (unionT s)).
    Context (Punion_none : ∀ s vs τs,
      Γ !! s = Some τs → (Γ,Γm) ⊢* vs :* τs → Forall2 P vs τs →
      vals_representable Γ Γm vs τs → P (VUnionAll s vs) (unionT s)).
    Definition val_typed_ind : ∀ v τ, val_typed' Γ Γm v τ → P v τ.
    Proof.
      fix 3; destruct 1; simplify_equality;
        eauto using Forall_impl, Forall2_impl.
    Qed.
  End val_typed_ind.

  Global Instance type_of_val: TypeOf (type Ti) (val Ti) := λ v,
    match v with
    | VBase vb => baseT (type_of vb)
    | VArray τ vs => τ.[length vs]
    | VStruct s _ => structT s
    | VUnion s _ _ | VUnionAll s _ => unionT s
    end.

  Definition val_new (Γ : env Ti) (τ : type Ti) : val Ti :=
    val_unflatten Γ τ (replicate (bit_size_of Γ τ) BIndet).
  Definition val_flatten (Γ : env Ti) : val Ti → list (bit Ti) :=
    fix go v :=
    match v with
    | VBase vb => base_val_flatten Γ vb
    | VArray _ vs => vs ≫= go
    | VStruct s vs =>
       default [] (Γ !! s) $ λ τs,
         let szs := field_bit_sizes Γ τs in
         mjoin (zip_with (λ w sz, resize sz BIndet (go w)) vs szs)
    | VUnion s i v => resize (bit_size_of Γ (unionT s)) BIndet (go v)
    | VUnionAll s vs =>
       let sz := bit_size_of Γ (unionT s) in
       from_option (replicate sz BIndet) (bits_list_join sz (go <$> vs))
    end.

  Fixpoint to_val (Γ : env Ti) (w : mtree Ti) : val Ti :=
    match w with
    | MBase τb bs => VBase (base_val_unflatten Γ τb (tagged_tag <$> bs))
    | MArray τ ws => VArray τ (to_val Γ <$> ws)
    | MStruct s wxbss => VStruct s (to_val Γ ∘ fst <$> wxbss)
    | MUnion s i w _ => VUnion s i (to_val Γ w)
    | MUnionAll s bs => val_unflatten Γ (unionT s) (tagged_tag <$> bs)
    end.
  Definition array_of_val (Γ : env Ti) (f : list perm → val Ti → mtree Ti) :
      list perm → list (val Ti) → list (mtree Ti) :=
    fix go xs vs :=
    match vs with
    | [] => []
    | v :: vs =>
       let sz := bit_size_of Γ (type_of v) in
       f (take sz xs) v :: go (drop sz xs) vs
    end.
  Definition struct_of_val (Γ : env Ti) (f : list perm → val Ti → mtree Ti) :
      list perm → list (val Ti) → list nat → list (mtree Ti * list (pbit Ti)) :=
    fix go xs vs pads :=
    match vs, pads with
    | v :: vs, pad :: pads =>
       let sz := bit_size_of Γ (type_of v) in
       let xs' := drop sz xs in
       (f (take sz xs) v,
        flip PBit BIndet <$> take pad xs') :: go (drop pad xs') vs pads
    | _, _ => []
    end.
  Fixpoint of_val (Γ : env Ti) (xs : list perm) (v : val Ti) : mtree Ti :=
    match v with
    | VBase vb =>
       MBase (type_of vb) (zip_with PBit xs (base_val_flatten Γ vb))
    | VArray τ vs => MArray τ (array_of_val Γ (of_val Γ) xs vs)
    | VStruct s vs =>
       let pads := field_bit_padding Γ (type_of <$> vs) in
       MStruct s (struct_of_val Γ (of_val Γ) xs vs pads)
    | VUnion s i v =>
       let sz := bit_size_of Γ (type_of v) in
       MUnion s i (of_val Γ (take sz xs) v) (flip PBit BIndet <$> drop sz xs)
    | VUnionAll s vs =>
       MUnionAll s (zip_with PBit xs (val_flatten Γ (VUnionAll s vs)))
    end.

  Global Instance vtype_check:
      TypeCheck (env Ti * memenv Ti) (type Ti) (val Ti) :=
    fix go (ΓΓm : _ * _) v {struct v} := let _ : TypeCheck _ _ _ := @go in
    let (Γ,Γm) := ΓΓm in
    match v with
    | VBase vb => TBase <$> type_check (Γ,Γm) vb
    | VArray τ vs =>
       guard (length vs ≠ 0);
       τs ← mapM (type_check (Γ,Γm)) vs;
       guard (Forall (τ =) τs);
       Some (τ.[length vs])
    | VStruct s vs =>
       τs ← Γ !! s;
       τs' ← mapM (type_check (Γ,Γm)) vs;
       guard ((τs' : list (type Ti)) = τs);
       Some (structT s)
    | VUnion s i v =>
       τ ← Γ !! s ≫= (!! i);
       τ' ← type_check (Γ,Γm) v;
       guard ((τ' : type Ti) = τ);
       Some (unionT s)
    | VUnionAll s vs =>
       τs ← Γ !! s;
       τs' ← mapM (type_check (Γ,Γm)) vs;
       guard (τs = τs');
       let sz := bit_size_of Γ (unionT s) in
       bs ← bits_list_join sz (val_flatten Γ <$> vs);
       guard (vs = (λ τ, val_unflatten Γ τ (take (bit_size_of Γ τ) bs)) <$> τs);
       Some (unionT s)
    end.

  Global Instance val_lookup_seg:
      LookupE (env Ti) (ref_seg Ti) (val Ti) (val Ti) := λ Γ rs v,
    match rs, v with
    | RArray i τ n, VArray τ' vs =>
       guard (n = length vs); guard (τ = τ'); vs !! i
    | RStruct i s, VStruct s' vs => guard (s = s'); vs !! i
    | RUnion i s β, VUnion s' j v =>
       guard (s = s');
       if decide (i = j) then Some v else
       guard (β = false);
       τ ← Γ !! s ≫= (!! i);
       let bs := resize (bit_size_of Γ τ) BIndet (val_flatten Γ v) in
       Some (val_unflatten Γ τ bs)
    | RUnion i s _, VUnionAll s' vs => guard (s = s'); vs !! i
    | _, _ => None
    end.
  Global Instance val_lookup: LookupE (env Ti) (ref Ti) (val Ti) (val Ti) :=
    fix go Γ r v := let _ : LookupE _ _ _ _ := @go in
    match r with [] => Some v | rs :: r => v !!{Γ} r ≫= lookupE Γ rs end.
  Definition val_alter_seg (Γ : env Ti) (g : val Ti → val Ti)
      (rs : ref_seg Ti) (v : val Ti) : val Ti :=
    match rs, v with
    | RArray i _ _, VArray τ vs => VArray τ (alter g i vs)
    | RStruct i _, VStruct s vs => VStruct s (alter g i vs)
    | RUnion i _ _, VUnion s j v' =>
       if decide (i = j) then VUnion s i (g v')
       else default v (Γ !! s ≫= (!! i)) $ λ τ,
         let bs := resize (bit_size_of Γ τ) BIndet (val_flatten Γ v) in
         VUnion s i (g (val_unflatten Γ τ bs))
    | RUnion i s _, VUnionAll _ vs => default v (vs !! i) (VUnion s i ∘ g)
    | _, _ => v
    end.
  Fixpoint val_alter (Γ : env Ti) (g : val Ti → val Ti)
      (r : ref Ti) : val Ti → val Ti :=
    match r with [] => g | rs :: r => val_alter Γ (val_alter_seg Γ g rs) r end.

  Inductive val_union_free : val Ti → Prop :=
    | VBase_union_free vb : val_union_free (VBase vb)
    | VArray_union_free τ vs :
       Forall (val_union_free) vs → val_union_free (VArray τ vs)
    | VStruct_union_free s vs :
       Forall val_union_free vs → val_union_free (VStruct s vs)
    | VUnionAll_union_free s vs :
       Forall val_union_free vs → val_union_free (VUnionAll s vs).
  Section val_union_free_ind.
    Context (Γ : env Ti) (P : val Ti → Prop).
    Context (Pbase : ∀ vb, P (VBase vb)).
    Context (Parray : ∀ τ vs,
      Forall val_union_free vs → Forall P vs → P (VArray τ vs)).
    Context (Pstruct : ∀ s vs,
      Forall val_union_free vs → Forall P vs → P (VStruct s vs)).
    Context (Punion_none : ∀ s vs,
      Forall val_union_free vs → Forall P vs → P (VUnionAll s vs)).
    Definition val_union_free_ind_alt: ∀ v, val_union_free v → P v.
    Proof. fix 2; destruct 1; eauto using Forall_impl. Qed.
  End val_union_free_ind.
  Global Instance val_union_free_dec: ∀ v, Decision (val_union_free v).
  Proof.
   refine (
    fix go v :=
    match v return Decision (val_union_free v) with
    | VBase v => left _
    | VArray _ vs => cast_if (decide (Forall val_union_free vs))
    | VStruct _ vs => cast_if (decide (Forall val_union_free vs))
    | VUnion s i v => right _
    | VUnionAll _ vs => cast_if (decide (Forall val_union_free vs))
    end); clear go; abstract first [by constructor | by inversion 1].
  Defined.
End operations.

Section values.
Context `{EnvSpec Ti}.
Implicit Types Γ : env Ti.
Implicit Types α : bool.
Implicit Types Γm : memenv Ti.
Implicit Types τb : base_type Ti.
Implicit Types τ : type Ti.
Implicit Types τs : list (type Ti).
Implicit Types b : bit Ti.
Implicit Types bs : list (bit Ti).
Implicit Types x : perm.
Implicit Types xs : list perm.
Implicit Types xb : pbit Ti.
Implicit Types xbs : list (pbit Ti).
Implicit Types w : mtree Ti.
Implicit Types ws : list (mtree Ti).
Implicit Types rs : ref_seg Ti.
Implicit Types r : ref Ti.
Implicit Types vb : base_val Ti.
Implicit Types v : val Ti.
Implicit Types vs : list (val Ti).
Notation vals_unflatten Γ τs bs :=
  ((λ τ, val_unflatten Γ τ (take (bit_size_of Γ τ) bs)) <$> τs).

Local Infix "⊑*" := (Forall2 bit_weak_refine) (at level 70).
Hint Extern 0 (_ ⊑* _) => reflexivity.
Hint Resolve Forall_take Forall_drop Forall_app_2
  Forall_replicate Forall_resize.
Hint Resolve Forall2_take Forall2_drop Forall2_app
  Forall2_replicate Forall2_resize.
Hint Resolve BIndet_valid BIndet_weak_refine.
Hint Immediate env_valid_lookup env_valid_lookup_lookup.
Hint Extern 0 (Separation _) => apply (_ : Separation (pbit Ti)).

(** ** Properties of the [val_flatten] function *)
Lemma val_flatten_length Γ Γm τ v :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length (val_flatten Γ v) = bit_size_of Γ τ.
Proof.
  intros HΓ Hvτ. revert v τ Hvτ. refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * intros. by erewrite base_val_flatten_length by eauto.
  * intros vs τ _ IH _. rewrite bit_size_of_array.
    induction IH; csimpl; rewrite ?app_length; auto.
  * intros s vs τs Hs Hvs IH.
    rewrite (bit_size_of_struct _ _ τs), Hs by done; simpl; clear Hs.
    revert vs Hvs IH. induction (bit_size_of_fields _ τs HΓ)
      as [|τ sz ?? Hn]; intros; decompose_Forall_hyps; [done |].
    rewrite app_length, resize_length; f_equal. eauto.
  * intros. by rewrite resize_length.
  * intros s vs τs Hs Hvs IH Hrep.
    destruct (bits_list_join _ _) as [bs'|] eqn:Hbs'; simpl.
    + eauto using bits_list_join_length.
    + by rewrite replicate_length.
Qed.
Lemma val_flatten_valid Γ Γm v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → ✓{Γ,Γm}* (val_flatten Γ v).
Proof.
  intros HΓ Hvτ. revert v τ Hvτ. refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * eauto using base_val_flatten_valid.
  * intros vs τ Hvs IH _. induction IH; decompose_Forall_hyps; auto.
  * intros s vs τs Hs Hvs IH. rewrite Hs; simpl; clear Hs. revert vs Hvs IH.
    induction (bit_size_of_fields _ τs HΓ);intros; decompose_Forall_hyps; auto.
  * eauto.
  * intros s vs τs Hs Hvs IH Hrep.
    destruct (bits_list_join _ _) as [bs'|] eqn:Hbs'; simpl; auto.
    eapply bits_list_join_valid; eauto. elim IH; csimpl; auto.
Qed.
Lemma val_flatten_weaken Γ1 Γ2 Γm1 v τ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm1) ⊢ v : τ → val_flatten Γ1 v = val_flatten Γ2 v.
Proof.
  intros ??. revert v τ. refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * eauto using base_val_flatten_weaken.
  * intros vs τ _ IH _. induction IH; f_equal'; auto.
  * intros s vs τs Hs _ IH.
    erewrite Hs, lookup_weaken by eauto; simpl.
    erewrite field_bit_sizes_weaken by eauto; f_equal; clear Hs.
    generalize (field_bit_sizes Γ2 τs).
    induction IH; intros [|??]; f_equal'; auto with f_equal.
  * intros; f_equal; eauto using bit_size_of_weaken, TCompound_valid.
  * intros s vs τs Hs _ IH _;
      do 2 f_equal; eauto using bit_size_of_weaken, TCompound_valid.
    elim IH; intros; f_equal'; auto.
Qed.

Ltac solve_length := repeat first
  [ rewrite take_length | rewrite drop_length | rewrite app_length
  | rewrite resize_length | rewrite fmap_length | rewrite replicate_length
  | erewrite ctree_flatten_length by eauto|erewrite val_flatten_length by eauto
  | rewrite zip_with_length | erewrite base_val_flatten_length by eauto
  | match goal with
    | |- context [ bit_size_of ?Γ ?τ ] =>
      match goal with
      | H : Γ !! ?s = Some ?τs, H2 : ?τs !! _ = Some τ |- _ =>
        unless (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s)) by done;
        assert (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s))
          by eauto using bit_size_of_union_lookup
      | H : Γ !! ?s = Some [?τ] |- _ =>
        unless (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s)) by done;
        assert (bit_size_of Γ τ ≤ bit_size_of Γ (unionT s))
          by eauto using bit_size_of_union_singleton
      end
    end]; lia.
Hint Extern 0 (length _ = _) => solve_length.
Hint Extern 0 (_ ≤ length _) => solve_length.
Hint Extern 0 (length _ ≤ _) => solve_length.

(** ** Properties of the [val_unflatten] function *)
Lemma val_unflatten_base Γ τb :
  val_unflatten Γ τb = λ bs, VBase (base_val_unflatten Γ τb bs).
Proof. unfold val_unflatten. by rewrite type_iter_base. Qed. 
Lemma val_unflatten_array Γ τ n :
  val_unflatten Γ (τ.[n]) = λ bs,
    VArray τ (array_unflatten Γ (val_unflatten Γ τ) τ n bs).
Proof. unfold val_unflatten. by rewrite type_iter_array. Qed.
Lemma val_unflatten_compound Γ c s τs bs :
  ✓ Γ → Γ !! s = Some τs → val_unflatten Γ (compoundT{c} s) bs =
    match c with
    | Struct_kind => VStruct s (struct_unflatten Γ (λ τ bs,
       let τsz := bit_size_of Γ τ in val_unflatten Γ τ (take τsz bs)) τs bs)
    | Union_kind => VUnionAll s (vals_unflatten Γ τs bs)
    end.
Proof.
  intros HΓ Hs. unfold val_unflatten. erewrite (type_iter_compound
    (pointwise_relation (list (bit Ti)) (@eq (val Ti))) _ _ _ _); try done.
  { intros ???????; f_equal. by apply array_unflatten_weaken. }
  clear s τs Hs bs. intros f g [] s τs Hs Hτs ? bs; f_equal.
  { eapply struct_unflatten_weaken, Forall_impl; eauto. }
  eapply Forall_fmap_ext, Forall_impl; eauto.
Qed.
Lemma val_unflatten_weaken Γ1 Γ2 τ bs :
  ✓ Γ1 → ✓{Γ1} τ → Γ1 ⊆ Γ2 → val_unflatten Γ1 τ bs = val_unflatten Γ2 τ bs.
Proof.
  intros. apply (type_iter_weaken (pointwise_relation _ (=))); try done.
  { intros ???. by erewrite base_val_unflatten_weaken by eauto. }
  { intros ???????; f_equal. by apply array_unflatten_weaken. }
  clear bs. intros f g [] s τs Hs Hτs Hfg bs; f_equal; auto.
  { eapply struct_unflatten_weaken, Forall_impl; eauto 1.
    auto using bit_size_of_weaken with f_equal. }
  clear Hs. induction Hfg; decompose_Forall_hyps; f_equal;
    auto using bit_size_of_weaken with f_equal.
Qed.
Lemma vals_unflatten_weaken Γ1 Γ2 τs bs :
  ✓ Γ1 → ✓{Γ1}* τs → Γ1 ⊆ Γ2 →
  vals_unflatten Γ1 τs bs = vals_unflatten Γ2 τs bs.
Proof.
  induction 2; intros; f_equal'; auto.
  by erewrite bit_size_of_weaken, val_unflatten_weaken by eauto.
Qed.
Lemma val_unflatten_typed Γ Γm τ bs :
  ✓ Γ → ✓{Γ} τ → ✓{Γ,Γm}* bs → length bs = bit_size_of Γ τ →
  (Γ,Γm) ⊢ val_unflatten Γ τ bs : τ.
Proof.
  intros HΓ Hτ. revert τ Hτ bs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb Hτ bs Hbs Hbs'. rewrite val_unflatten_base.
    typed_constructor; auto using base_val_unflatten_typed.
  * intros τ n Hτ IH Hn bs; rewrite val_unflatten_array, bit_size_of_array.
    intros Hbs Hbs'. typed_constructor; eauto using array_unflatten_length.
    revert bs Hbs Hbs'. clear Hn. induction n; simpl; auto.
  * intros [] s τs Hs Hτs IH _ bs; erewrite val_unflatten_compound,
       ?bit_size_of_struct by eauto; intros Hbs Hbs'.
    { typed_constructor; eauto. unfold struct_unflatten.
      revert bs Hbs Hbs'. clear Hs Hτs. induction (bit_size_of_fields _ τs HΓ);
        intros; decompose_Forall_hyps; auto. }
    typed_constructor; eauto.
    { clear Hτs. pose proof (bit_size_of_union _ _ _ HΓ Hs); clear Hs.
      induction IH; decompose_Forall_hyps; auto. }
    exists bs; auto. rewrite Hbs'. auto using bit_size_of_union.
Qed.
Lemma vals_unflatten_typed Γ Γm τs bs :
  ✓ Γ → ✓{Γ}* τs → ✓{Γ,Γm}* bs → Forall (λ τ, bit_size_of Γ τ ≤ length bs) τs →
  (Γ,Γm) ⊢* vals_unflatten Γ τs bs :* τs.
Proof.
  induction 2; intros; decompose_Forall_hyps; auto using val_unflatten_typed.
Qed.
Lemma vals_representable_typed Γ Γm vs τs :
  ✓ Γ → ✓{Γ}* τs → vals_representable Γ Γm vs τs → (Γ,Γm) ⊢* vs :* τs.
Proof. intros ?? [bs ?? ->]. auto using vals_unflatten_typed. Qed.
Lemma val_unflatten_type_of Γ τ bs :
  ✓ Γ → ✓{Γ} τ → type_of (val_unflatten Γ τ bs) = τ.
Proof.
  intros HΓ Hτ. revert τ Hτ bs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb _ bs. rewrite val_unflatten_base; simpl.
    by rewrite base_val_unflatten_type_of.
  * intros τ [|n] _ IH ? bs; [done|]. rewrite val_unflatten_array; simpl.
    by rewrite array_unflatten_length.
  * intros [] s τs ? _ _ _ bs; by erewrite val_unflatten_compound by eauto.
Qed.
Lemma vals_unflatten_type_of Γ τs bs :
  ✓ Γ → ✓{Γ}* τs → type_of <$> vals_unflatten Γ τs bs = τs.
Proof. induction 2; f_equal'; auto using val_unflatten_type_of. Qed.
Lemma vals_unflatten_representable Γ Γm bs τs :
  ✓{Γ,Γm}* bs → Forall (λ τ, bit_size_of Γ τ ≤ length bs) τs →
  vals_representable Γ Γm (vals_unflatten Γ τs bs) τs.
Proof. by exists bs. Qed.
Lemma val_unflatten_frozen Γ Γm τ bs :
  ✓ Γ → ✓{Γ,Γm}* bs →
  val_freeze true (val_unflatten Γ τ bs) = val_unflatten Γ τ bs.
Proof.
  intros HΓ. revert τ bs. refine (weak_type_env_ind _ HΓ _ _ _ _ _).
  * intros. rewrite val_unflatten_base; simpl.
    by rewrite base_val_unflatten_frozen by eauto.
  * intros τ n IH bs Hbs. rewrite val_unflatten_array; f_equal'. revert bs Hbs.
    induction n; intros; f_equal'; auto.
  * intros [] s τs Hs IH bs Hbs;
      erewrite val_unflatten_compound by eauto; f_equal'; clear Hs.
    { unfold struct_unflatten. revert bs Hbs.
      induction (bit_size_of_fields _ τs HΓ); intros;
        decompose_Forall_hyps; f_equal; auto. }
    revert bs Hbs; induction IH; intros; f_equal'; eauto.
  * intros c s Hs bs Hbs.
    unfold val_unflatten; rewrite type_iter_compound_None by eauto.
    destruct c; f_equal'. unfold struct_unflatten; simpl; auto.
    rewrite !field_bit_sizes_nil by done. repeat constructor.
Qed.
Lemma vals_unflatten_frozen Γ Γm τs bs :
  ✓ Γ → ✓{Γ,Γm}* bs →
  val_freeze true <$> vals_unflatten Γ τs bs = vals_unflatten Γ τs bs.
Proof. intros. induction τs; f_equal'; eauto using val_unflatten_frozen. Qed.
Lemma val_unflatten_union_free Γ τ bs :
  ✓ Γ → val_union_free (val_unflatten Γ τ bs).
Proof.
  intros HΓ. revert τ bs. refine (weak_type_env_ind _ HΓ _ _ _ _ _).
  * intros. rewrite val_unflatten_base. by constructor.
  * intros τ n IH bs. rewrite val_unflatten_array. constructor.
    revert bs. induction n; simpl; auto.
  * intros [] s τs Hs IH bs; erewrite !val_unflatten_compound by eauto.
    { constructor. unfold struct_unflatten. revert bs. clear Hs.
      induction (bit_size_of_fields _ τs HΓ);
        intros; decompose_Forall_hyps; auto. }
    constructor. elim IH; csimpl; auto.
  * intros c s Hs bs. unfold val_unflatten;
      rewrite type_iter_compound_None by done; simpl.
    destruct c; repeat constructor.
    unfold struct_unflatten. rewrite field_bit_sizes_nil by done. constructor.
Qed.
Lemma val_unflatten_between Γ τ bs1 bs2 bs3 :
  ✓ Γ → ✓{Γ} τ → bs1 ⊑* bs2 → bs2 ⊑* bs3 → length bs1 = bit_size_of Γ τ →
  val_unflatten Γ τ bs1 = val_unflatten Γ τ bs3 →
  val_unflatten Γ τ bs2 = val_unflatten Γ τ bs3.
Proof.
  intros HΓ Hτ. revert τ Hτ bs1 bs2 bs3. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb ? bs1 bs2 bs3 ??.
    rewrite !val_unflatten_base, !(injective_iff VBase).
    by apply base_val_unflatten_between.
  * intros τ n ? IH _ bs1 bs2 bs3 Hbs1 Hbs2. rewrite !val_unflatten_array,
       bit_size_of_array, !(injective_iff (VArray _)).
    revert bs1 bs2 bs3 Hbs1 Hbs2.
    induction n; intros; simplify_equality'; f_equal'; eauto.
  * intros [] s τs Hs Hτs IH _ bs1 bs2 bs3 Hbs1 Hbs2;
      erewrite !val_unflatten_compound, ?bit_size_of_struct by eauto.
    { rewrite !(injective_iff (VStruct s)). clear Hs Hτs.
      revert bs1 bs2 bs3 Hbs1 Hbs2. unfold struct_unflatten.
      induction (bit_size_of_fields _ τs HΓ); intros ???; simpl;
        rewrite ?take_take; intros; decompose_Forall_hyps; f_equal; eauto. }
    pose proof (bit_size_of_union _ _ _ HΓ Hs). clear Hs Hτs.
    rewrite !(injective_iff (VUnionAll s)). revert bs1 bs2 bs3 Hbs1 Hbs2.
    induction IH; intros; decompose_Forall_hyps; f_equal; eauto.
Qed.
Lemma vals_unflatten_between Γ τs bs1 bs2 bs3 :
  ✓ Γ → ✓{Γ}* τs → bs1 ⊑* bs2 → bs2 ⊑* bs3 →
  Forall (λ τ, bit_size_of Γ τ ≤ length bs1) τs →
  vals_unflatten Γ τs bs1 = vals_unflatten Γ τs bs3 →
  vals_unflatten Γ τs bs2 = vals_unflatten Γ τs bs3.
Proof.
  induction 2; intros; decompose_Forall_hyps; f_equal;
    eauto using val_unflatten_between.
Qed.
Global Opaque val_unflatten.

(** ** General properties of the typing judgment *)
Lemma val_typed_int_frozen Γ Γm v τi :
  (Γ,Γm) ⊢ v : intT τi → val_freeze true v = v.
Proof. inversion_clear 1;simpl. by erewrite base_typed_int_frozen by eauto. Qed.
Lemma val_union_free_base Γ Γm v τb : (Γ,Γm) ⊢ v : baseT τb → val_union_free v.
Proof. inversion 1; constructor. Qed.
Lemma val_typed_type_valid Γ Γm v τ : ✓ Γ → (Γ,Γm) ⊢ v : τ → ✓{Γ} τ.
Proof.
  induction 2 using @val_typed_ind; econstructor; decompose_Forall_hyps;
    try match goal with
    | H : length ?vs ≠ 0, H2 : Forall _ ?vs |- _ => destruct H2; [done|]
    end; eauto; eapply base_val_typed_type_valid; eauto.
Qed.
Lemma val_typed_types_valid Γ Γm vs τs : ✓ Γ → (Γ,Γm) ⊢* vs :* τs → ✓{Γ}* τs.
Proof. induction 2; constructor; eauto using val_typed_type_valid. Qed.
Global Instance: TypeOfSpec (env Ti * memenv Ti) (type Ti) (val Ti).
Proof.
  intros [Γ Γm]. induction 1 using @val_typed_ind; decompose_Forall_hyps;
    f_equal; eauto; eapply type_of_correct; eauto.
Qed.
Lemma vals_representable_weaken Γ1 Γ2 Γm1 Γm2 vs τs :
  ✓ Γ1 → ✓{Γ1}* τs → vals_representable Γ1 Γm1 vs τs → Γ1 ⊆ Γ2 →
  Γm1 ⇒ₘ Γm2 → vals_representable Γ2 Γm2 vs τs.
Proof.
  intros ? Hτs [bs ? Hlen Hvs]. exists bs.
  * eauto using Forall_impl, bit_valid_weaken.
  * clear Hvs. induction Hτs; decompose_Forall_hyps; constructor; auto 2.
    by erewrite <-bit_size_of_weaken by eauto.
  * by erewrite <-vals_unflatten_weaken by eauto.
Qed.
Lemma val_typed_weaken Γ1 Γ2 Γm1 Γm2 v τ :
  ✓ Γ1 → (Γ1,Γm1) ⊢ v : τ → Γ1 ⊆ Γ2 → Γm1 ⇒ₘ Γm2 → (Γ2,Γm2) ⊢ v : τ.
Proof.
  intros ? Hvτ ??. induction Hvτ using @val_typed_ind; econstructor;
    erewrite <-1?vals_unflatten_weaken;
    erewrite <-1?bit_size_of_weaken by eauto using TCompound_valid;
    eauto using base_val_typed_weaken, @lookup_weaken, vals_representable_weaken,
      Forall_impl, bit_valid_weaken, val_typed_types_valid.
Qed.
Lemma val_freeze_freeze β1 β2 v :
  val_map (freeze β1) (val_map (freeze β2) v) = val_map (freeze β1) v.
Proof.
  assert (∀ vs, Forall (λ v, val_map (freeze β1)
      (val_map (freeze β2) v) = val_map (freeze β1) v) vs →
    val_map (freeze β1) <$> val_map (freeze β2) <$> vs =
      val_map (freeze β1) <$> vs).
  { induction 1; f_equal'; auto. }
  induction v using val_ind_alt; f_equal'; auto using base_val_freeze_freeze.
Qed.
Lemma vals_freeze_freeze β1 β2 vs :
  val_map (freeze β1) <$> val_map (freeze β2) <$> vs
  = val_map (freeze β1) <$> vs.
Proof. induction vs; f_equal'; auto using val_freeze_freeze. Qed.
Lemma vals_representable_freeze Γ Γm vs τs :
  ✓ Γ → vals_representable Γ Γm vs τs →
  vals_representable Γ Γm (val_freeze true <$> vs) τs.
Proof. intros ? [bs ?? ->]. exists bs; eauto using vals_unflatten_frozen. Qed.
Lemma typed_freeze Γ Γm v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → (Γ,Γm) ⊢ val_freeze true v : τ.
Proof.
  induction 2 using @val_typed_ind; simplify_equality'.
  * typed_constructor. by apply base_typed_freeze.
  * typed_constructor; auto using fmap_length. by apply Forall_fmap.
  * typed_constructor; eauto. by apply Forall2_fmap_l.
  * typed_constructor; eauto.
  * typed_constructor; eauto using vals_representable_freeze.
    by apply Forall2_fmap_l.
Qed.
Lemma val_union_free_freeze β v :
  val_union_free (val_map (freeze β) v) ↔ val_union_free v.
Proof.
  split.
  * assert (∀ vs, Forall (λ v,
        val_union_free (val_map (freeze β) v) → val_union_free v) vs →
      Forall val_union_free (val_map (freeze β) <$> vs) →
      Forall val_union_free vs).
    { induction 1; csimpl; intros; decompose_Forall; eauto. } 
    induction v using val_ind_alt; inversion_clear 1; econstructor; eauto.
  * induction 1 using @val_union_free_ind_alt; simpl;
      econstructor; eauto; by apply Forall_fmap.
Qed.

(** ** Interaction between [val_flatten] and [val_unflatten] *)
Lemma val_union_to_bits_valid Γ Γm sz vs τs bs :
  ✓ Γ → bits_list_join sz (val_flatten Γ <$> vs) = Some bs →
  (Γ,Γm) ⊢* vs :* τs → ✓{Γ,Γm}* bs.
Proof.
  intros ? Hbs Hvs. eapply bits_list_join_valid; eauto.
  elim Hvs; intros; constructor; eauto using val_flatten_valid.
Qed.
Lemma val_flatten_unflatten Γ Γm τ bs :
  ✓ Γ → ✓{Γ} τ → ✓{Γ,Γm}* bs → length bs = bit_size_of Γ τ →
  val_flatten Γ (val_unflatten Γ τ bs) ⊑* bs.
Proof.
  intros HΓ Hτ. revert τ Hτ bs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb ? bs ?. rewrite val_unflatten_base; simpl.
    eauto using base_val_flatten_unflatten.
  * intros τ n Hτ IH _ bs. rewrite val_unflatten_array; simpl.
    rewrite bit_size_of_array. revert bs.
    induction n as [|n IHn]; simpl; intros bs ??.
    { by erewrite nil_length_inv by eauto. }
    apply Forall2_app_l;
      erewrite val_flatten_length by eauto using val_unflatten_typed; auto.
  * intros [] s τs Hs Hτs IH _ bs; erewrite val_unflatten_compound,
      ?bit_size_of_struct by eauto; simpl; intros Hbs Hbs'.
    { rewrite Hs; simpl. clear Hs Hτs. revert bs Hbs Hbs'.
      unfold struct_unflatten. induction (bit_size_of_fields _ τs HΓ)
        as [|τ sz τs szs]; intros bs ??; decompose_Forall_hyps.
      { by erewrite nil_length_inv by eauto. }
      apply Forall2_app_l; rewrite resize_length, <-?(resize_le _ _ BIndet),
        ?resize_resize by done; eauto using Forall2_resize_r, Forall_true. }
    destruct (bits_list_join _ _) as [bs'|] eqn:Hbs''; simpl.
    { apply bit_size_of_union in Hs; auto. revert bs' Hbs''.
      induction IH as [|τ τs]; intros bs' Hbs'';
        decompose_Forall_hyps; simplify_option_equality.
      { eauto using Forall2_replicate_l, resize_length, Forall_true. }
      eapply bits_join_min; eauto. rewrite <-?(resize_le _ _ BIndet) by done.
      eauto using Forall2_resize_r_flip, Forall_true. }
    auto using Forall2_replicate_l, Forall_true, resize_length.
Qed.
Lemma vals_representable_as_bits_aux Γ Γm sz vs τs :
  ✓ Γ → ✓{Γ}* τs → Forall (λ τ, bit_size_of Γ τ ≤ sz) τs →
  Forall2 (λ v τ, val_union_free v →
    val_unflatten Γ τ (val_flatten Γ v) = val_freeze true v) vs τs →
  vals_representable Γ Γm vs τs →
  ∃ bs, bits_list_join sz (val_flatten Γ <$> vs) = Some bs ∧
    ✓{Γ,Γm}* bs ∧ vs = vals_unflatten Γ τs bs.
Proof.
  intros HΓ Hτs Hsz IH [bs' ? Hlen ->].
  destruct (bits_list_join_exists sz (val_flatten Γ <$> vals_unflatten Γ τs bs')
    (resize sz BIndet bs')) as (bs&Hbs&Hbsbs').
  { by rewrite resize_length. }
  { clear IH. induction Hτs; decompose_Forall_hyps; constructor; auto.
    rewrite <-?(resize_le _ _ BIndet) by done.
    eauto using Forall2_resize_r, Forall_true, val_flatten_unflatten. }
  exists bs. split_ands; [done| |].
  { assert ((Γ,Γm) ⊢* vals_unflatten Γ τs bs' :* τs) as Hτs'
      by auto using vals_unflatten_typed.
    eapply bits_list_join_valid; eauto. clear Hsz IH Hbs Hbsbs'.
    induction Hτs'; decompose_Forall_hyps; eauto using val_flatten_valid. }
  apply bits_list_join_Some_alt in Hbs.
  induction Hτs as [|τ τs ?? IHτs]; simplify_equality'; auto.
  apply Forall2_cons_inv in IH; destruct IH as [IH IH'].
  apply Forall_cons in Hbs; destruct Hbs as [Hbs Hbs'].
  decompose_Forall_hyps; f_equal; auto; clear IH' Hbs' IHτs.
  symmetry; apply (val_unflatten_between _ _
    (val_flatten Γ (val_unflatten Γ τ (take (bit_size_of Γ τ) bs')))
    (take (bit_size_of Γ τ) bs) (take (bit_size_of Γ τ) bs')); auto 1.
  * apply (Forall2_take _ _ _ (bit_size_of Γ τ)) in Hbs.
    rewrite take_resize_le, resize_all_alt in Hbs; auto 1.
    by erewrite val_flatten_length by eauto using val_unflatten_typed.
  * apply (Forall2_take _ _ _ (bit_size_of Γ τ)) in Hbsbs'.
    rewrite take_resize_le, resize_le in Hbsbs'; eauto.
  * by erewrite val_flatten_length by eauto using val_unflatten_typed.
  * by erewrite IH, val_unflatten_frozen
      by eauto using val_unflatten_union_free.
Qed.
Lemma val_unflatten_flatten Γ Γm τ v :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → val_union_free v →
  val_unflatten Γ τ (val_flatten Γ v) = val_freeze true v.
Proof.
  intros HΓ. revert v τ. refine (val_typed_ind _ _ _ _ _ _ _ _).
  * intros vb τb ? _. rewrite val_unflatten_base; f_equal'.
    eauto using base_val_unflatten_flatten.
  * intros vs τ ? IH _; inversion_clear 1.
    rewrite val_unflatten_array; f_equal'.
    induction IH; decompose_Forall_hyps;
      rewrite ?take_app_alt, ?drop_app_alt by auto; f_equal; auto.
  * intros s vs τs Hs Hvs IH; inversion_clear 1.
    erewrite val_unflatten_compound by eauto; simpl; rewrite Hs; f_equal'.
    unfold struct_unflatten. clear Hs. revert dependent vs.
    induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
      rewrite ?take_app_alt, ?drop_app_alt; f_equal; auto.
    rewrite take_resize_le, resize_all_alt by auto; auto.
  * intros s i τs v τ Hs Hτs Hv IH. inversion_clear 1.
  * intros s vs τs Hs Hvs IH Hrepr _.
    erewrite val_unflatten_compound by eauto; simpl.
    destruct (vals_representable_as_bits_aux Γ Γm
      (bit_size_of Γ (unionT s)) vs τs) as (bs&->&?&->);
      eauto using bit_size_of_union; simpl.
    by erewrite vals_unflatten_frozen by eauto.
Qed.
Lemma vals_representable_as_bits Γ Γm sz vs τs :
  ✓ Γ → ✓{Γ}* τs → Forall (λ τ, bit_size_of Γ τ ≤ sz) τs →
  vals_representable Γ Γm vs τs →
  ∃ bs, bits_list_join sz (val_flatten Γ <$> vs) = Some bs ∧ length bs = sz ∧
    ✓{Γ,Γm}* bs ∧ vs = vals_unflatten Γ τs bs.
Proof.
  intros ??? Hvs. destruct (vals_representable_as_bits_aux Γ Γm sz vs τs)
    as (?&?&?&?); eauto 6 using bits_list_join_length.
  apply vals_representable_typed in Hvs; auto.
  elim Hvs; constructor; eauto using val_unflatten_flatten.
Qed.

(** ** Properties of the [val_new] function *)
Lemma val_new_base Γ τb :
  val_new Γ τb = VBase (if decide (τb = voidT%BT) then VVoid else VIndet τb).
Proof.
  unfold val_new; rewrite val_unflatten_base. case_decide; subst; [done|].
  by rewrite base_val_unflatten_indet by auto.
Qed.
Lemma val_new_array Γ τ n :
  val_new Γ (τ.[n]) = VArray τ (replicate n (val_new Γ τ)).
Proof.
  unfold val_new; rewrite val_unflatten_array, bit_size_of_array; f_equal.
  by induction n; f_equal'; rewrite ?take_replicate_plus, ?drop_replicate_plus.
Qed.
Lemma val_new_compound Γ c s τs :
  ✓ Γ → Γ !! s = Some τs → val_new Γ (compoundT{c} s) =
    match c with
    | Struct_kind => VStruct s (val_new Γ <$> τs)
    | Union_kind => VUnionAll s (val_new Γ <$> τs)
    end.
Proof.
  intros HΓ Hs; unfold val_new; erewrite val_unflatten_compound by eauto.
  destruct c; f_equal.
  * erewrite ?bit_size_of_struct by eauto; clear Hs.
    unfold struct_unflatten, field_bit_padding.
    by induction (bit_size_of_fields _ τs HΓ); decompose_Forall_hyps;
      rewrite ?take_replicate_plus, ?drop_replicate_plus, ?take_replicate,
      ?drop_replicate, ?Min.min_l, ?fmap_replicate by done; repeat f_equal.
  * eapply Forall_fmap_ext, Forall_impl; [eapply bit_size_of_union; eauto|].
    intros. by rewrite take_replicate, Min.min_l by done.
Qed.
Lemma val_new_weaken Γ1 Γ2 τ :
  ✓ Γ1 → ✓{Γ1} τ → Γ1 ⊆ Γ2 → val_new Γ1 τ = val_new Γ2 τ.
Proof.
  intros. unfold val_new.
  by erewrite val_unflatten_weaken, bit_size_of_weaken by eauto.
Qed.
Lemma val_new_typed Γ Γm τ : ✓ Γ → ✓{Γ} τ → (Γ,Γm) ⊢ val_new Γ τ : τ.
Proof. intros; apply val_unflatten_typed; auto using replicate_length. Qed.
Lemma vals_new_typed Γ Γm τs :
  ✓ Γ → ✓{Γ}* τs → (Γ,Γm) ⊢* val_new Γ <$> τs :* τs.
Proof. induction 2; simpl; eauto using val_new_typed. Qed.
Lemma val_new_type_of Γ τ : ✓ Γ → ✓{Γ} τ → type_of (val_new Γ τ) = τ.
Proof. by apply val_unflatten_type_of. Qed.
Lemma val_new_frozen Γ τ :
  ✓ Γ → ✓{Γ} τ → val_freeze true (val_new Γ τ) = val_new Γ τ.
Proof. intros. apply (val_unflatten_frozen Γ ∅); auto. Qed.
Lemma val_new_union_free Γ τ : ✓ Γ → val_union_free (val_new Γ τ).
Proof. intros. by apply val_unflatten_union_free. Qed.

(** ** Properties of the [to_val] function *)
Lemma to_val_typed Γ Γm w τ :
  ✓ Γ → (Γ,Γm) ⊢ w : τ → (Γ,Γm) ⊢ to_val Γ w : τ.
Proof.
  intros HΓ. induction 1 using @ctree_typed_ind; simpl.
  * typed_constructor.
    eauto using base_val_unflatten_typed, pbits_tag_valid.
  * typed_constructor; auto using fmap_length. by apply Forall_fmap.
  * typed_constructor; eauto. by apply Forall2_fmap_l.
  * typed_constructor; eauto.
  * eauto using val_unflatten_typed, TCompound_valid, pbits_tag_valid.
Qed.
Lemma to_vals_typed Γ Γm ws τs :
  ✓ Γ → (Γ,Γm) ⊢* ws :* τs → (Γ,Γm) ⊢* to_val Γ <$> ws :* τs.
Proof. induction 2; csimpl; auto using to_val_typed. Qed.
Lemma to_val_type_of Γ w :
  ✓ Γ → ✓{Γ} (type_of w) → type_of (to_val Γ w) = type_of w.
Proof.
  intros HΓ. induction w as [|τ ws IH| | |] using @ctree_ind_alt; simpl; auto.
  * by rewrite base_val_unflatten_type_of.
  * intros. by rewrite val_unflatten_type_of.
Qed.
Lemma to_val_frozen Γ Γm w τ :
  ✓ Γ → (Γ,Γm) ⊢ w : τ → val_freeze true (to_val Γ w) = to_val Γ w.
Proof.
  induction 2 using @ctree_typed_ind; simpl.
  * by erewrite base_val_unflatten_frozen by eauto using pbits_tag_valid.
  * f_equal. rewrite <-list_fmap_compose. by apply Forall_fmap_ext.
  * f_equal. rewrite <-list_fmap_compose.
    eapply Forall_fmap_ext, Forall2_Forall_l; eauto. eapply Forall_true; eauto.
  * by f_equal.
  * eauto using val_unflatten_frozen, TCompound_valid, pbits_tag_valid.
Qed.
Lemma to_val_union_free Γ w :
  ✓ Γ → union_free w → val_union_free (to_val Γ w).
Proof.
  intros HΓ. by induction 1 using @union_free_ind_alt; simpl;
    try econstructor; eauto using val_unflatten_union_free, TCompound_valid,
    val_new_union_free; decompose_Forall.
Qed.
Lemma to_val_union_free_inv Γ w : val_union_free (to_val Γ w) → union_free w.
Proof.
  induction w as [|ws IH|s wxbss IH| | ] using @ctree_ind_alt;
    simpl; inversion_clear 1; econstructor; eauto.
  * induction IH; decompose_Forall_hyps; auto.
  * induction IH; decompose_Forall_hyps; auto.
Qed.
Lemma to_val_unflatten Γ τ xbs :
  ✓ Γ → ✓{Γ} τ → to_val Γ (ctree_unflatten Γ τ xbs)
  = val_unflatten Γ τ (tagged_tag <$> xbs).
Proof.
  intros HΓ Hτ. revert τ Hτ xbs. refine (type_env_ind _ HΓ _ _ _ _).
  * intros τb _ xbs. by rewrite ctree_unflatten_base, val_unflatten_base.
  * intros τ n _ IH _ xbs.
    rewrite ctree_unflatten_array, val_unflatten_array; f_equal'. revert xbs.
    induction n; intros; f_equal'; rewrite <-?fmap_drop, <-?fmap_take; auto.
  * intros [] s τs Hs _ IH _ xbs; erewrite ctree_unflatten_compound,
      val_unflatten_compound by eauto; f_equal'.
    { unfold struct_unflatten. clear Hs. revert xbs.
      induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
        rewrite <-?fmap_drop, <-?fmap_take; f_equal'; auto. }
    by erewrite val_unflatten_compound by eauto.
Qed.

(** ** Properties of the [of_val] function *)
Lemma ctree_flatten_of_val Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ →
  ctree_flatten (of_val Γ xs v) = zip_with PBit xs (val_flatten Γ v).
Proof.
  intros HΓ Hv. revert v τ Hv xs. refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * done.
  * intros vs τ Hvs IH _ xs; rewrite bit_size_of_array; revert xs.
    induction IH; intros xs Hxs; decompose_Forall_hyps;
      erewrite ?zip_with_nil_r, ?type_of_correct,
      ?zip_with_app_r, ?val_flatten_length by eauto; f_equal; auto.
  * intros s vs τs Hs Hvs IH xs.
    erewrite Hs, bit_size_of_struct, fmap_type_of by eauto; simpl.
    unfold field_bit_padding. clear Hs. revert vs Hvs IH xs.
    induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
      erewrite ?zip_with_nil_r, ?type_of_correct, ?resize_ge,
      <-?(associative_L (++)), ?zip_with_app_r, ?val_flatten_length,
      ?replicate_length, ?zip_with_replicate_r by eauto; repeat f_equal; auto.
  * intros s i τs v τ ??? IH xs ?. erewrite type_of_correct, resize_ge,
      zip_with_app_r, val_flatten_length, zip_with_replicate_r by eauto.
    f_equal; auto.
  * done.
Qed.
Lemma ctree_flatten_of_val' Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ →
  tagged_tag <$> ctree_flatten (of_val Γ xs v) = val_flatten Γ v.
Proof. intros. by erewrite ctree_flatten_of_val, fmap_zip_with_r by eauto. Qed.
Lemma of_val_unshared Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ → Forall sep_unshared xs →
  Forall (not ∘ sep_unmapped) xs → ctree_unshared (of_val Γ xs v).
Proof.
  intros. erewrite ctree_flatten_of_val by eauto; eauto using PBits_unshared.
Qed.
Lemma of_val_mapped Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ →
  Forall (not ∘ sep_unmapped) xs →
  ctree_Forall (not ∘ sep_unmapped) (of_val Γ xs v).
Proof.
  intros. erewrite ctree_flatten_of_val by eauto. eauto using PBits_mapped.
Qed.
Lemma of_val_typed Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ → Forall sep_valid xs →
  Forall (not ∘ sep_unmapped) xs → (Γ,Γm) ⊢ of_val Γ xs v : τ.
Proof.
  intros HΓ Hv. revert v τ Hv xs. refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * intros vb τb ? xs ???. erewrite type_of_correct by eauto.
    typed_constructor.
    + eauto using base_val_typed_type_valid.
    + eauto using PBits_valid, base_val_flatten_valid.
    + erewrite zip_with_length, base_val_flatten_length by eauto; lia.
  * intros vs τ Hvs IH Hvs' xs. rewrite bit_size_of_array; intros Hlen  Hxs Hxs'.
    typed_constructor; trivial.
    + clear Hvs Hvs' Hxs Hxs' Hlen IH. revert xs.
      induction vs; intros; f_equal'; auto.
    + revert xs Hxs Hxs' Hlen. clear Hvs'. induction IH; intros;
        decompose_Forall_hyps; erewrite ?type_of_correct by eauto;
        constructor; auto.
  * intros s vs τs Hs Hvs IH xs.
    erewrite bit_size_of_struct, fmap_type_of by eauto; intros Hlen Hxs Hxs'.
    typed_constructor; eauto; clear Hs; unfold field_bit_padding.
    + revert vs xs Hvs IH Hxs Hxs' Hlen.
      induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
        erewrite ?type_of_correct by eauto; constructor; simpl; auto.
    + clear IH. revert vs xs Hvs Hxs Hxs' Hlen.
      induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
        erewrite ?type_of_correct by eauto; constructor; simpl; auto.
      erewrite <-zip_with_replicate_r by eauto; eauto 7 using PBits_valid.
    + clear Hxs Hxs' Hlen IH. revert xs vs Hvs.
      induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
        constructor; simpl; eauto using PBits_indetify.
    + clear Hxs Hxs' IH. revert vs xs Hvs Hlen.
      induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
        erewrite ?type_of_correct by eauto; f_equal; auto.
  * intros. erewrite type_of_correct by eauto. typed_constructor; eauto.
    + erewrite <-zip_with_replicate_l, zip_with_flip by eauto.
      auto using PBits_valid.
    + auto using PBits_indetify.
    + rewrite fmap_length; solve_length.
    + intros [Hc _]. eapply (ctree_Forall_not sep_unmapped Γ Γm
        (of_val Γ (take (bit_size_of Γ τ) xs) v)); eauto using of_val_mapped.
  * intros s vs τs Hs Hvs IH Hrep xs ???.
    destruct (bits_list_join _ _) as [bs'|] eqn:Hbs'; simpl.
    { typed_constructor; eauto.
      + eauto using PBits_valid, val_union_to_bits_valid.
      + erewrite zip_with_length, bits_list_join_length by eauto; auto; lia. }
    typed_constructor; eauto using PBits_valid.
Qed.
Lemma of_val_weaken Γ1 Γ2 Γm1 xs v τ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm1) ⊢ v : τ → of_val Γ1 xs v = of_val Γ2 xs v.
Proof.
  intros HΓ ? Hv. revert v τ Hv xs. refine (val_typed_ind _ _ _ _ _ _ _ _).
  * intros; f_equal'; eauto using base_val_flatten_weaken with f_equal.
  * intros vs τ ? IH _ xs; f_equal'; revert xs.
    induction IH; intros; decompose_Forall_hyps; simplify_type_equality;
      erewrite ?(bit_size_of_weaken Γ1 Γ2) by eauto using val_typed_type_valid;
      auto with f_equal.
  * intros s vs τs Hs Hvs IH xs; f_equal'; revert xs.
    erewrite fmap_type_of, field_bit_padding_weaken by eauto; clear Hs.
    generalize (field_bit_padding Γ2 τs).
    induction IH; intros [|??] ?; decompose_Forall_hyps; simplify_type_equality;
      erewrite ?bit_size_of_weaken by eauto using val_typed_type_valid;
      auto with f_equal.
  * intros; simplify_type_equality'.
    erewrite bit_size_of_weaken by eauto using val_typed_type_valid.
    auto with f_equal.
  * intros; unfold of_val; do 2 f_equal; eapply val_flatten_weaken; eauto.
    econstructor; eauto.
Qed.
Lemma of_val_type_of Γ xs v : type_of (of_val Γ xs v) = type_of v.
Proof.
  destruct v as [|? vs _| | |] using val_ind_alt;
    simplify_equality'; rewrite ?fmap_length; f_equal; auto.
  revert xs; induction vs; intros; f_equal'; auto.
Qed.
Lemma to_of_val Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ →
  to_val Γ (of_val Γ xs v) = val_freeze true v.
Proof.
  intros HΓ Hvτ. revert v τ Hvτ xs.
  refine (val_typed_ind _ _ _ _ _ _ _ _); simpl.
  * intros. by erewrite type_of_correct, fmap_zip_with_r,
      base_val_unflatten_flatten by eauto.
  * intros vs τ Hvs IH _ xs; rewrite bit_size_of_array; intros Hxs; f_equal.
    revert xs Hxs. induction IH; intros; decompose_Forall_hyps;
      erewrite ?type_of_correct by eauto; f_equal; auto.
  * intros s vs τs Hs Hvs IH xs; erewrite fmap_type_of,
      bit_size_of_struct by eauto; intros Hxs; f_equal.
    revert vs xs Hvs IH Hxs. unfold field_bit_padding. clear Hs.
    induction (bit_size_of_fields _ τs HΓ); intros; decompose_Forall_hyps;
      erewrite ?type_of_correct by eauto; f_equal; eauto.
  * intros; erewrite type_of_correct by eauto; f_equal; auto.
  * intros s vs τs Hs Hvs IH Hrepr xs ?.
    destruct (vals_representable_as_bits Γ Γm (bit_size_of Γ (unionT s)) vs τs)
     as (bs&->&?&?&Hbs); simpl; eauto using bit_size_of_union.
    by erewrite fmap_zip_with_r,
      val_unflatten_compound, Hbs, vals_unflatten_frozen by eauto.
Qed.
Lemma of_val_union_free Γ xs v :
  val_union_free v → union_free (of_val Γ xs v).
Proof.
  intros Hv. revert xs. induction Hv as [|? vs _ IH|s vs _ IH|]
    using @val_union_free_ind_alt; intros xs; simpl; econstructor; eauto.
  * revert xs. induction IH; simpl; constructor; auto.
  * generalize (field_bit_padding Γ (type_of <$> vs)). revert xs.
    induction IH; intros ? [|??]; constructor; simpl; auto.
Qed.
Lemma of_val_union_free_inv Γ Γm xs v τ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → length xs = bit_size_of Γ τ →
  union_free (of_val Γ xs v) → val_union_free v.
Proof.
  intros. erewrite <-(val_union_free_freeze true),
    <-(to_of_val _ _ xs) by eauto. by apply to_val_union_free.
Qed.
Lemma to_val_new Γ τ :
  ✓ Γ → ✓{Γ} τ → to_val Γ (ctree_new Γ pbit_full τ) = val_new Γ τ.
Proof.
  intros. unfold ctree_new. by rewrite to_val_unflatten, fmap_replicate.
Qed.
Lemma of_val_new Γ τ x :
  ✓ Γ → ✓{Γ} τ →
  of_val Γ (replicate (bit_size_of Γ τ) x) (val_new Γ τ)
  = ctree_new Γ (PBit x BIndet) τ.
Proof.
  intros HΓ. revert τ. refine (type_env_ind _ HΓ _ _ _ _).
  * intros. rewrite ctree_new_base, val_new_base.
    by case_decide; simplify_equality'; rewrite zip_with_replicate.
  * intros τ n ? IH _.
    rewrite bit_size_of_array, val_new_array, ctree_new_array; f_equal'.
    induction n; simpl; rewrite ?val_new_type_of, ?take_replicate,
      ?Min.min_l, ?drop_replicate_plus by (auto with lia); f_equal; auto.
  * intros [] s τs Hs Hτs IH _; erewrite val_new_compound,
      ctree_new_compound, ?bit_size_of_struct by eauto; f_equal'.
    { clear Hs. erewrite fmap_type_of by eauto using (vals_new_typed _ ∅).
      unfold field_bit_padding.
      induction (bit_size_of_fields _ τs HΓ) as [|τ sz τs szs ?? IH'];
        decompose_Forall_hyps; auto.
      rewrite val_new_type_of, !drop_replicate, !take_replicate, !Min.min_l,
        fmap_replicate, <-IH' by auto with lia; repeat f_equal; auto with lia. }
    destruct (bits_list_join_exists (bit_size_of Γ (unionT s))
      (val_flatten Γ <$> val_new Γ <$> τs)
      (replicate (bit_size_of Γ (unionT s)) BIndet)) as (bs'&->&?); auto.
    { apply Forall_fmap, Forall_fmap; apply (Forall_impl ✓{Γ}); auto.
      intros τ ?; simpl. unfold val_new.
      by rewrite (val_flatten_unflatten _ ∅), resize_replicate by eauto. }
    erewrite (bits_subseteq_indets bs') by eauto using Forall_replicate_eq.
    apply zip_with_replicate.
Qed.
Lemma ctree_map_of_val Γ f g xs v :
  (∀ x b, f (PBit x b) = PBit (g x) b) →
  ctree_map f (of_val Γ xs v) = of_val Γ (g <$> xs) v.
Proof.
  intros ?. revert xs. assert (∀ xs bs,
    f <$> zip_with PBit xs bs = zip_with PBit (g <$> xs) bs).
  { induction xs; intros [|??]; f_equal'; auto. }
  assert (∀ xs, f <$> flip PBit BIndet <$> xs = flip PBit BIndet <$> g <$> xs).
  { intros. rewrite <-!list_fmap_compose. apply list_fmap_ext; simpl; auto. }
  induction v as [|τ vs IH|s vs IH| |] using @val_ind_alt; simpl;
    intros xs; rewrite <-?fmap_drop, <-?fmap_take; f_equal'; revert xs; auto.
  * induction IH; intros; f_equal'; rewrite <-?fmap_take, <-?fmap_drop; auto.
  * generalize (field_bit_padding Γ (type_of <$> vs)).
    induction IH; intros [|??] ?; f_equal';
      rewrite <-?fmap_drop, <-?fmap_take; auto with f_equal.
Qed.

(** ** Decidable typing *)
Local Arguments type_check _ _ _ _ _ !_ /.
Global Instance:
  TypeCheckSpec (env Ti * memenv Ti) (type Ti) (val Ti) (✓ ∘ fst).
Proof.
  intros [Γ Γm] v τ ?; revert v τ. assert (∀ vs τs,
    Forall (λ v, ∀ τ, type_check (Γ,Γm) v = Some τ → (Γ,Γm) ⊢ v : τ) vs →
    mapM (type_check (Γ,Γm)) vs = Some τs → (Γ,Γm) ⊢* vs :* τs).
  { intros vs τs. rewrite mapM_Some. intros. decompose_Forall; eauto. }
  assert (∀ vs τ,
    (Γ,Γm) ⊢* vs : τ → Forall (λ v, type_check (Γ,Γm) v = Some τ) vs →
    mapM (type_check (Γ,Γm)) vs = Some (replicate (length vs) τ)).
  { intros. apply mapM_Some, Forall2_replicate_r;decompose_Forall_hyps; eauto. }
  intros v τ; split.
  * revert τ. induction v using @val_ind_alt; intros; simplify_option_equality.
    + typed_constructor; auto. by apply type_check_sound.
    + typed_constructor; eauto using @Forall2_Forall_typed.
    + typed_constructor; decompose_Forall_hyps; eauto.
    + typed_constructor; eauto.
    + typed_constructor; eauto. apply vals_unflatten_representable.
      - eapply bits_list_join_valid, Forall_fmap,
          Forall2_Forall_l, Forall_true; eauto using val_flatten_valid.
      - erewrite bits_list_join_length by eauto. eauto using bit_size_of_union.
  * induction 1 using @val_typed_ind; simplify_option_equality.
    + by erewrite type_check_complete by eauto.
    + done.
    + erewrite mapM_Some_2; eauto. by simplify_option_equality.
    + done.
    + erewrite mapM_Some_2; eauto; simplify_option_equality.
      by match goal with
      | _ : Γ !! ?s = Some _, H : vals_representable ?Γ ?m ?vs ?τs |- _ =>
        destruct (vals_representable_as_bits Γ Γm
          (bit_size_of Γ (unionT s)) vs τs) as (?&?&?&?&->);
          eauto using val_typed_types_valid, bit_size_of_union
      end; simplify_option_equality.
Qed.

(** ** Properties of lookup *)
Lemma val_lookup_nil Γ : lookupE (A:=val Ti) Γ [] = Some.
Proof. done. Qed.
Lemma val_lookup_cons Γ rs r :
  lookupE Γ (rs :: r) = λ v, v !!{Γ} r ≫= lookupE Γ rs.
Proof. done. Qed.
Lemma val_lookup_app Γ v r1 r2: v !!{Γ} (r1 ++ r2) = v !!{Γ} r2 ≫= lookupE Γ r1.
Proof.
  induction r1 as [|rs1 r1 IH]; simpl.
  * by destruct (v !!{Γ} r2).
  * by rewrite !val_lookup_cons, IH, option_bind_assoc.
Qed.
Lemma val_lookup_snoc Γ v r rs: v !!{Γ} (r ++ [rs]) = v !!{Γ} rs ≫= lookupE Γ r.
Proof. apply val_lookup_app. Qed.
Lemma val_lookup_seg_Some Γ Γm v τ rs v' :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} rs = Some v' →
  ∃ σ, Γ ⊢ rs : τ ↣ σ ∧ (Γ,Γm) ⊢ v' : σ.
Proof.
  intros ?. destruct 1 as [|vs τ n _|s vs τs ? Hvs _|s j τs v τ
    |s vs τs ?? _ [bs ?? ->]] using @val_typed_ind;
    destruct rs as [i|i|i]; intros Hlookup; simplify_option_equality.
  * exists τ. split.
    + constructor; eauto using lookup_lt_Some.
    + eapply (Forall_lookup (λ v, (Γ,Γm) ⊢ v : τ)); eauto.
  * destruct (Forall2_lookup_l _ _ _ i v' Hvs) as (σ&?&?); eauto.
    exists σ; split; [|done]. typed_constructor; eauto.
  * exists τ; split; [|done]. typed_constructor; eauto.
  * eexists; split; eauto using val_unflatten_typed, val_flatten_valid.
    econstructor; eauto.
  * apply list_lookup_fmap_inv in Hlookup; destruct Hlookup as (τ&->&?).
    decompose_Forall_hyps. exists τ; split; [econstructor; eauto|].
    eauto using val_unflatten_typed.
Qed.
Lemma val_lookup_Some Γ Γm v τ r v' :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} r = Some v' →
  ∃ σ, Γ ⊢ r : τ ↣ σ ∧ (Γ,Γm) ⊢ v' : σ.
Proof.
  intros ?. revert v τ.
  induction r as [|rs r IH] using rev_ind; intros v τ Hvτ Hr.
  { simplify_type_equality. exists τ; split; [econstructor |]; eauto. }
  rewrite val_lookup_snoc in Hr.
  destruct (v !!{Γ} rs) as [v''|] eqn:Hv''; simplify_equality'.
  destruct (val_lookup_seg_Some Γ Γm v τ rs v'') as (σ''&?&?); auto.
  destruct (IH v'' σ'') as (σ&?&?); auto.
  exists σ; split; [eapply ref_typed_snoc|]; eauto.
Qed.
Lemma val_lookup_seg_typed Γ Γm v τ rs v' σ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} rs = Some v' →
  Γ ⊢ rs : τ ↣ σ → (Γ,Γm) ⊢ v' : σ.
Proof.
  intros. by destruct (val_lookup_seg_Some Γ Γm v τ rs v')
    as (σ'&Hrσ'&?); simplify_type_equality.
Qed.
Lemma val_lookup_typed Γ Γm v τ r v' σ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} r = Some v' → Γ ⊢ r : τ ↣ σ → (Γ,Γm) ⊢ v' : σ.
Proof.
  intros. by destruct (val_lookup_Some Γ Γm v τ r v')
    as (σ'&Hrσ'&?); simplify_type_equality.
Qed.
Lemma val_lookup_seg_weaken Γ1 Γ2 Γm1 rs v τ v' :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm1) ⊢ v : τ →
  v !!{Γ1} rs = Some v' → v !!{Γ2} rs = Some v'.
Proof.
  intros ?? Hv Hrs. destruct Hv, rs; simplify_option_equality; auto.
  erewrite lookup_weaken by eauto; simplify_option_equality.
  by erewrite <-bit_size_of_weaken, <-val_flatten_weaken,
    <-val_unflatten_weaken by eauto.
Qed.
Lemma val_lookup_weaken Γ1 Γ2 Γm1 r v τ v' :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm1) ⊢ v : τ →
  v !!{Γ1} r = Some v' → v !!{Γ2} r = Some v'.
Proof.
  intros ??. revert v'. induction r as [|rs r IH]; intros v3; [done|].
  rewrite !val_lookup_cons, bind_Some; intros ? (v2&?&?).
  destruct (val_lookup_Some Γ1 Γm1 v τ r v2) as (τ2&?&?); auto.
  erewrite IH by eauto; simpl; eauto using val_lookup_seg_weaken.
Qed.
Lemma val_lookup_weaken_is_Some Γ1 Γ2 Γm1 r v τ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm1) ⊢ v : τ →
  is_Some (v !!{Γ1} r) → is_Some (v !!{Γ2} r).
Proof. intros ??? [??]; eauto using val_lookup_weaken. Qed.
Lemma to_val_lookup_seg Γ w rs w' :
  ✓ Γ → w !!{Γ} rs = Some w' → frozen rs →
  to_val Γ w !!{Γ} rs = Some (to_val Γ w').
Proof.
  intros ? Hr. destruct w; destruct rs; pattern w';
    apply (ctree_lookup_seg_inv _ _ _ _ _ Hr); intros; simplify_option_equality.
  * rewrite list_lookup_fmap. by simplify_option_equality.
  * rewrite list_lookup_fmap. by simplify_option_equality.
  * done.
  * erewrite val_unflatten_compound, to_val_unflatten by eauto.
    by simplify_option_equality;
      rewrite list_lookup_fmap, fmap_take; simplify_option_equality.
Qed.
Lemma to_val_lookup Γ w r w' :
  ✓ Γ → w !!{Γ} r = Some w' → freeze true <$> r = r →
  to_val Γ w !!{Γ} r = Some (to_val Γ w').
Proof.
  intros ?. revert w. induction r using rev_ind; intros w.
  { by rewrite ctree_lookup_nil; intros; simplify_equality. }
  rewrite ctree_lookup_snoc, fmap_app; intros;
    simplify_option_equality; simplify_list_equality.
  erewrite val_lookup_snoc, to_val_lookup_seg by eauto; eauto.
Qed.

(** ** Properties of alter *)
Implicit Types g : val Ti → val Ti.
Lemma val_alter_nil Γ g : val_alter Γ g [] = g.
Proof. done. Qed.
Lemma val_alter_cons Γ g rs r :
  val_alter Γ g (rs :: r) = val_alter Γ (val_alter_seg Γ g rs) r.
Proof. done. Qed.
Lemma val_alter_singleton Γ g rs : val_alter Γ g [rs] = val_alter_seg Γ g rs.
Proof. done. Qed.
Lemma val_alter_app Γ g v r1 r2 :
  val_alter Γ g (r1 ++ r2) v = val_alter Γ (val_alter Γ g r1) r2 v.
Proof.
  revert g. induction r1; simpl; intros; rewrite ?val_alter_cons; auto.
Qed.
Lemma val_alter_snoc Γ g v r rs :
  val_alter Γ g (r ++ [rs]) v = val_alter_seg Γ (val_alter Γ g r) rs v.
Proof. apply val_alter_app. Qed.
Lemma val_alter_seg_freeze Γ β g rs :
  val_alter_seg Γ g (freeze β rs) = val_alter_seg Γ g rs.
Proof. by destruct rs. Qed.
Lemma val_alter_freeze Γ β g r :
  val_alter Γ g (freeze β <$> r) = val_alter Γ g r.
Proof.
  revert g. induction r as [|rs r IH]; intros g; simpl; [done |].
  by rewrite IH, val_alter_seg_freeze.
Qed.
Lemma val_alter_seg_ext Γ g1 g2 v rs :
  (∀ v', g1 v' = g2 v') → val_alter_seg Γ g1 rs v = val_alter_seg Γ g2 rs v.
Proof.
  intros. destruct rs, v; simpl; unfold default; simplify_option_equality;
    repeat case_match; f_equal; auto using list_fmap_ext, list_alter_ext.
Qed.
Lemma val_alter_ext Γ g1 g2 v r :
  (∀ v', g1 v' = g2 v') → val_alter Γ g1 r v = val_alter Γ g2 r v.
Proof.
  intros. revert v. induction r as [|rs r IH] using rev_ind; intros v; [done|].
  rewrite !val_alter_snoc. by apply val_alter_seg_ext.
Qed.
Lemma val_alter_seg_ext_typed Γ Γm g1 g2 v τ rs :
  ✓ Γ → (∀ v' τ', (Γ,Γm) ⊢ v' : τ' → g1 v' = g2 v') → (Γ,Γm) ⊢ v : τ →
  val_alter_seg Γ g1 rs v = val_alter_seg Γ g2 rs v.
Proof.
  intros ? Hg. destruct rs, 1; simpl;
    unfold default; simplify_option_equality; f_equal; auto.
  * apply list_alter_ext; intros; decompose_Forall. eapply Hg; eauto. done.
  * apply list_alter_ext; intros; decompose_Forall. eapply Hg; eauto. done.
  * f_equal; eauto.
  * repeat case_match; f_equal; eauto using val_new_typed.
    eapply Hg; eauto using val_unflatten_typed, val_flatten_valid.
  * repeat case_match; decompose_Forall; f_equal. eapply Hg; eauto.
Qed.
Lemma val_alter_ext_typed Γ Γm g1 g2 v τ r :
  ✓ Γ → (∀ v' τ', (Γ,Γm) ⊢ v' : τ' → g1 v' = g2 v') → (Γ,Γm) ⊢ v : τ →
  val_alter Γ g1 r v = val_alter Γ g2 r v.
Proof.
  intros ?. revert g1 g2 v τ.
  induction r as [|rs r IH]; intros g1 g2 v τ ??; eauto.
  rewrite !val_alter_cons; eauto using val_alter_seg_ext_typed.
Qed.
Lemma val_alter_seg_compose Γ g1 g2 v rs :
  val_alter_seg Γ (g1 ∘ g2) rs v
  = val_alter_seg Γ g1 rs (val_alter_seg Γ g2 rs v).
Proof.
  destruct v, rs; simpl; unfold default;
    repeat (simplify_option_equality || case_match);
    f_equal; auto using list_alter_compose.
Qed.
Lemma val_alter_compose Γ g1 g2 v r :
  val_alter Γ (g1 ∘ g2) r v = val_alter Γ g1 r (val_alter Γ g2 r v).
Proof.
  intros. revert v. induction r as [|rs r IH] using rev_ind; intros w; [done|].
  rewrite !val_alter_snoc, <-val_alter_seg_compose. by apply val_alter_seg_ext.
Qed.
Lemma val_alter_seg_commute Γ g1 g2 v rs1 rs2 :
  rs1 ⊥ rs2 → val_alter_seg Γ g1 rs1 (val_alter_seg Γ g2 rs2 v)
  = val_alter_seg Γ g2 rs2 (val_alter_seg Γ g1 rs1 v).
Proof.
  destruct 1, v; intros; simplify_option_equality;
    f_equal; auto using list_alter_commute.
Qed.
Lemma val_alter_commute Γ g1 g2 v r1 r2 :
  r1 ⊥ r2 → val_alter Γ g1 r1 (val_alter Γ g2 r2 v)
  = val_alter Γ g2 r2 (val_alter Γ g1 r1 v).
Proof.
  rewrite ref_disjoint_alt. intros (r1'&rs1'&r1''&r2'&rs2'&r2''&->&->&?&Hr).
  rewrite !val_alter_app, !val_alter_singleton.
  rewrite <-!(val_alter_freeze _ true _ r1''), !Hr, !val_alter_freeze.
  rewrite <-!val_alter_compose. apply val_alter_ext; intros w'; simpl; auto.
  by apply val_alter_seg_commute.
Qed.
Lemma val_alter_seg_weaken Γ1 Γ2 Γm g rs v τ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm) ⊢ v : τ →
  val_alter_seg Γ1 g rs v = val_alter_seg Γ2 g rs v.
Proof.
  destruct rs as [| |j], 3; simplify_option_equality; auto.
  erewrite (lookup_weaken Γ1 Γ2) by eauto; simpl.
  destruct (_ !! j) eqn:?; f_equal'.
  by erewrite !(bit_size_of_weaken Γ1 Γ2), val_unflatten_weaken,
    val_flatten_weaken by eauto using TCompound_valid.
Qed.
Lemma val_alter_weaken Γ1 Γ2 Γm g r v τ :
  ✓ Γ1 → Γ1 ⊆ Γ2 → (Γ1,Γm) ⊢ v : τ → val_alter Γ1 g r v = val_alter Γ2 g r v.
Proof.
  intros ??. revert g v τ. induction r as [|rs r IH]; intros g v τ ?; [done|].
  erewrite !val_alter_cons, <-IH by eauto.
  eapply val_alter_ext_typed; eauto using val_alter_seg_weaken.
Qed.
Lemma val_alter_seg_typed Γ Γm g v rs τ v' :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} rs = Some v' →
  (Γ,Γm) ⊢ g v' : type_of v' → (Γ,Γm) ⊢ val_alter_seg Γ g rs v : τ.
Proof.
  intros HΓ Hv Hrs.
  destruct rs, Hv; change (val_typed' Γ Γm) with (typed (Γ,Γm)) in *; intros;
    simplify_option_equality; decompose_Forall_hyps; simplify_type_equality;
    typed_constructor; eauto using alter_length.
  * apply Forall_alter; naive_solver.
  * apply Forall2_alter_l; naive_solver.
  * rewrite resize_resize by eauto using bit_size_of_union_lookup.
    erewrite <-val_unflatten_type_of by eauto; eauto.
Qed.
Lemma val_alter_typed Γ Γm g v r τ v' :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → v !!{Γ} r = Some v' →
  (Γ,Γm) ⊢ g v' : type_of v' → (Γ,Γm) ⊢ val_alter Γ g r v : τ.
Proof.
  intros HΓ. revert g τ v. induction r as [|rs r IH] using @rev_ind.
  { by intros; simplify_type_equality'. }
  intros g τ v; rewrite val_alter_snoc, val_lookup_snoc; intros.
  destruct (v !!{Γ} rs) as [v''|] eqn:?; simplify_equality'.
  destruct (val_lookup_seg_Some Γ Γm v τ rs v'') as (?&_&?); eauto.
  eapply val_alter_seg_typed; eauto using val_lookup_seg_typed, type_of_typed.
Qed.
Lemma val_alter_const_typed Γ Γm v r τ v' σ :
  ✓ Γ → (Γ,Γm) ⊢ v : τ → Γ ⊢ r : τ ↣ σ → is_Some (v !!{Γ} r) →
  (Γ,Γm) ⊢ v' : σ → (Γ,Γm) ⊢ val_alter Γ (λ _, v') r v : τ.
Proof.
  intros ??? [v'' ?] ?; eapply val_alter_typed; eauto.
  by erewrite type_of_correct by eauto using val_lookup_typed. 
Qed.
End values.
