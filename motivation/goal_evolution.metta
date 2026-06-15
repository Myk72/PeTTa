;; Incremental Goal Evolution
;;
;; Goals must evolve gradually. Never replace goals directly.
;;
;; Update rule:
;;   G_next = (1 - α) × G_current + α × G_proposed
;;
;; where α (learning rate) is adaptive:
;;   α = alphaMin + (alphaMax - alphaMin) × safety_score
;;   safety_score = gInd_over × (1 - risk) × (1 - threshold)
;;
;; AlphaBound min/max, GoalFloor, and GoalDeltaWeight atoms
;; are all read from registry.metta — no hardcoded numbers here.
;;
;; MetaMo deltaG:
;;   The winning candidate carries CandidateDeltaG atoms that propose
;;   goal adjustments. evolveGoalState blends both the appraisal-driven
;;   proposal AND the candidate-driven delta into the final value.


;; α bounds
(= (alphaMin)
   (let $v (collapse (match &self (AlphaBound min $x) $x))
      (if (== $v ()) 0.01 (car-atom $v))))

(= (alphaMax)
   (let $v (collapse (match &self (AlphaBound max $x) $x))
      (if (== $v ()) 0.15 (car-atom $v))))


;; Per-goal floor
;; Returns 0.0 for goals that have no GoalFloor atom registered.
(= (goalFloor $name)
   (let $v (collapse (match &self (GoalFloor $name $f) $f))
      (if (== $v ()) 0.0 (car-atom $v))))


;; Adaptive α computation
;; High gInd_over + low risk + low threshold → high α (safe to evolve faster).
(= (computeAlpha)
   (let* (
      ($gInd    (eval (fetchGoalValue gInd_over)))
      ($risk    (eval (getAppraisalDim risk)))
      ($thr     (eval (fetchModulatorValue threshold)))
      ($safety  (* $gInd (* (- 1.0 $risk) (- 1.0 $thr))))
      ($alpha   (+ (alphaMin) (* (- (alphaMax) (alphaMin)) $safety)))
   )
   (clamp $alpha)))


;; evolveGoal
;; Blends proposed value with current using α, then applies floor.
;; $proposed — appraisal-driven value (from proposedGoalValue)
;; $candidateDelta — extra nudge from the winning candidate's CandidateDeltaG
(= (evolveGoal $name $proposed $candidateDelta)
   (let* (
      ($current (eval (fetchGoalValue $name)))
      ($alpha   (eval (computeAlpha)))
      ;; α-blend with appraisal proposal
      ($blended (eval (clamp (+ (* (- 1.0 $alpha) $current)
                          (* $alpha $proposed)))))
      ;; Add candidate-driven nudge on top of blended result
      ($nudged  (eval (clamp (+ $blended $candidateDelta))))
      ;; Apply MetaMo floor: value cannot go below floor
      ($floor   (goalFloor $name))
      ($new     (if (> $floor 0.0)
                    (if (< $nudged $floor) $floor $nudged)
                    $nudged))
      ($_ (eval (replaceGoal $name $new)))
   )
   (goal $name $new)))


;; proposedGoalValue
;; Computes a proposed value for a single goal driven by the
;; current appraisal dimensions. Uses GoalDeltaWeight atoms from
;;
;; Special case: help_user uses verified-success signal presence
;; to choose between positive (progress) and negative (risk) deltas.
(= (proposedGoalValue $name)
   (let* (
      ($current  (eval (fetchGoalValue $name)))
      ($hasSuccess (let $s (collapse (match &signal-space (signal verified-success $_) yes))
                      (if (== $s ()) False True)))
      ;; Sum all registered GoalDeltaWeight contributions for this goal
      ($delta (sumList
                 (collapse
                    (let (GoalDeltaWeight $name $dim $scale)
                         (match &self (GoalDeltaWeight $name $dim $scale)
                                      (GoalDeltaWeight $name $dim $scale))
                    ;; For help_user/risk: only penalise when no success signal
                    (let $dimVal (getAppraisalDim $dim)
                       (if (and (== $name help_user)
                                (and (== $dim risk) $hasSuccess))
                           0.0
                           (* $scale $dimVal)))))
                 0.0))
   )
   (clamp (+ $current $delta))))


;; candidateGoalDelta
;; Returns the CandidateDeltaG contribution for a single goal
;; given the winning candidate name. Returns 0.0 when no atom exists.
(= (candidateGoalDelta $candidateName $goalName)
   (let $v (collapse (match &self (CandidateDeltaG $candidateName $goalName $d) $d))
      (if (== $v ()) 0.0 (car-atom $v))))


;; evolveGoalState
;; Applies proposedGoalValue + candidate deltaG + α-blending
;; to every GoalSpec goal.
;; $winningCandidate — name of the candidate selected by motivationalDecision
(= (evolveGoalState $winningCandidate)
   (let* (
      ($_ (println! ("Running goal evolution...")))
      ($updates (collapse
         (let (GoalSpec $name $_b)
              (match &self (GoalSpec $name $_b) (GoalSpec $name $_b))
          (evolveGoal $name
                      (proposedGoalValue $name)
                      (candidateGoalDelta $winningCandidate $name)))))
      ($_ (println! (eval (py-str ("Goal updates: " (repr $updates))))))
   )
   $updates))
