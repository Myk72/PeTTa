;; Motivational Decision Layer D

!(bind! &consecutive-safety-wins (new-state 0))


;; Anti-saturation config
(= (safetySaturationThreshold)
   (let $v (collapse (match &self (AntiSaturation threshold $x) $x))
      (if (== $v ()) 3 (car-atom $v))))

(= (safetySaturationStep)
   (let $v (collapse (match &self (AntiSaturation step $x) $x))
      (if (== $v ()) 0.06 (car-atom $v))))

(= (safetySaturationMax)
   (let $v (collapse (match &self (AntiSaturation max $x) $x))
      (if (== $v ()) 0.30 (car-atom $v))))



(= (floor01 $x)
   (if (< $x 0.01) 0.01 $x))



;; Goal Alignment — weighted sum of goal/motive values for this candidate
(= (computeGoalAlignment $cand)
   (let $contributions (collapse
         (let (CandidateGoalAlignment $cand $goal $weight)
              (match &self (CandidateGoalAlignment $cand $goal $weight)
                           (CandidateGoalAlignment $cand $goal $weight))
          (* $weight (fetchGoalOrMotiveValue $goal))))
   (sumList $contributions 0.0)))

;; Modulator Effects — signed sum of modulator values for candidate type
(= (computeModulatorEffects $cand)
   (let* (
      ($typeList (collapse (match &self (CandidateSpec $cand $t) $t)))
      ($type (if (== $typeList ()) execution (car-atom $typeList)))
      ($contributions (collapse
         (let (CandidateTypeModulator $type $mod $sign)
              (match &self (CandidateTypeModulator $type $mod $sign)
                           (CandidateTypeModulator $type $mod $sign))
          (let $modVal (fetchModulatorValue $mod)
             (if (< $sign 0.0)
                 (- 0.0 (* (- 0.0 $sign) $modVal))
                 (* $sign $modVal))))))
   )
   (sumList $contributions 0.0)))

;; Transcendence Bonus — growth candidates get gTrans_over boost
(= (computeTranscendenceBonus $cand)
   (let* (
      ($typeList (collapse (match &self (CandidateSpec $cand $t) $t)))
      ($type     (if (== $typeList ()) execution (car-atom $typeList)))
   )
   (if (== $type growth)
       (* (fetchGoalValue gTrans_over) 0.30)
       0.0)))

;; Stability Penalty — risky candidates penalised by gInd × securing
(= (computeStabilityPenalty $cand)
   (let* (
      ($rfList (collapse (match &self (CandidateRiskFactor $cand $r) $r)))
      ($rf     (if (== $rfList ()) 0.0 (car-atom $rfList)))
      ($gInd   (fetchGoalValue gInd_over))
      ($sec    (fetchModulatorValue securing))
   )
   (* $rf (* $gInd $sec))))

;; Risk Penalty — risky candidates penalised by threshold
(= (computeRiskPenalty $cand)
   (let* (
      ($rfList (collapse (match &self (CandidateRiskFactor $cand $r) $r)))
      ($rf     (if (== $rfList ()) 0.0 (car-atom $rfList)))
      ($thr    (fetchModulatorValue threshold))
   )
   (* $rf $thr)))

;; Anti-Saturation Penalty — breaks infinite defer/ask-clarification loops.
;; After safetySaturationThreshold consecutive safety wins, an escalating
;; penalty (saturationStep per extra win, capped at saturationMax) is applied.
(= (computeAntiSaturationPenalty $cand)
   (let* (
      ($typeList (collapse (match &self (CandidateSpec $cand $t) $t)))
      ($type     (if (== $typeList ()) execution (car-atom $typeList)))
      ($wins     (get-state &consecutive-safety-wins))
   )
   (if (and (== $type safety) (> $wins (safetySaturationThreshold)))
       (clamp (min (safetySaturationMax)
                   (* (safetySaturationStep) (- $wins (safetySaturationThreshold)))))
       0.0)))

;; Final candidate score
(= (scoreCandidate $cand)
   (let* (
      ($ga   (computeGoalAlignment $cand))
      ($me   (computeModulatorEffects $cand))
      ($tb   (computeTranscendenceBonus $cand))
      ($sp   (computeStabilityPenalty $cand))
      ($rp   (computeRiskPenalty $cand))
      ($asp  (computeAntiSaturationPenalty $cand))
      ($pos  (* (floor01 $ga) (* (floor01 $me) (+ 1.0 $tb))))
      ($score (clamp (- $pos (+ $sp (+ $rp $asp)))))
   )
   (scored-candidate $cand $score)))


;; Score all registered candidates
;; Reads CandidateSpec atoms from &self — always correct regardless
;; of &candidateSpace state.
(= (scoreAllCandidates)
   (collapse (let (CandidateSpec $cand $_type)
                  (match &self (CandidateSpec $cand $_type)
                               (CandidateSpec $cand $_type))
              (scoreCandidate $cand))))


;; Safety type check
(= (isSafetyCandidate $name)
   (let $typeList (collapse (match &self (CandidateSpec $name $t) $t))
      (if (== $typeList ())
          False
          (== (car-atom $typeList) safety))))


;; Fold to find the highest-scoring candidate
(= (foldScoredList () $best) $best)
(= (foldScoredList $lst $best)
   (let* (
      (($head $tail) (decons-atom $lst))
      ((scored-candidate $hn $hs) $head)
      ((scored-candidate $bn $bs) $best)
      ($nextBest (if (> $hs $bs) $head $best))
   )
   (foldScoredList $tail $nextBest)))


;; motivationalDecision
;; 1. Scores ALL registered candidates via scoreAllCandidates.
;; 2. Finds the winner by fold.
;; 3. Updates &consecutive-safety-wins for anti-saturation.
;; 4. Looks up mode + directive from CandidateDecisionMap.
;; 5. Updates &last-motivation-decision and replaces mode.
;; 6. Returns (motivational-result decision all-scores winning-candidate)
;;    — the winning candidate name is returned so bridge.metta can
;;      pass it to evolveGoalState for MetaMo deltaG wiring.

(= (motivationalDecision)
   (let* (
      ;; Score all registered candidates
      ($allScores (scoreAllCandidates))

      ;; Find best-scoring candidate
      ($initBest  (scored-candidate respond 0.0))
      ($best      (foldScoredList $allScores $initBest))
      ((scored-candidate $name $score) $best)

      ;; Generate candidate set for audit / context injection
      ($_ (generateCandidates))

      ;; Update anti-saturation counter
      ($_ (if (isSafetyCandidate $name)
              (change-state! &consecutive-safety-wins
                             (+ (get-state &consecutive-safety-wins) 1))
              (change-state! &consecutive-safety-wins 0)))

      ;; Look up mode + directive from registry
      ($mapList (collapse (match &self (CandidateDecisionMap $name $mode $directive)
                              (CandidateDecisionMap $name $mode $directive))))
      ($mode    (if (== $mapList ())
                    orient
                    (let (CandidateDecisionMap $_ $m $_d) (car-atom $mapList) $m)))
      ($dir     (if (== $mapList ())
                    inspect
                    (let (CandidateDecisionMap $_ $_m $d) (car-atom $mapList) $d)))

      ($decision (decision $name $mode $dir $score))

      ($_ (change-state! &last-motivation-decision $decision))
      ($_ (replaceMode $mode))

      ($_ (println! (eval (py-str ("Motivational decision: " (repr $decision))))))
   )
   ;; Return winning candidate name alongside result so bridge can use deltaG
   (motivational-result $decision $allScores $name)))
