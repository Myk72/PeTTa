;; Candidate Generation Layer

!(bind! &candidateSpace (new-space))

(= (clearCandidates)
   (clearSpace &candidateSpace))

(= (addCandidate $name)
   (add-atom &candidateSpace (candidate $name)))

;; Return all candidate names as a list.
(= (getCandidates)
   (collapse (match &candidateSpace (candidate $name) $name)))


(= (evalCondition always _ _)           True)
(= (evalCondition task-active _ _)      (taskIsActive))
(= (evalCondition appraisal-above $param $thresh)
   (> (getAppraisalDim $param) $thresh))
(= (evalCondition appraisal-below $param $thresh)
   (< (getAppraisalDim $param) $thresh))
(= (evalCondition modulator-above $param $thresh)
   (> (fetchModulatorValue $param) $thresh))
(= (evalCondition self-metric-above $param $thresh)
   (> (fetchSelfMetricValue $param) $thresh))
(= (evalCondition self-metric-below $param $thresh)
   (< (fetchSelfMetricValue $param) $thresh))

(= (taskIsActive)
   (hasContent (get-state &active-task)))


(= (candidateIsAvailable $name)
   (let $conditions (collapse (match &self (CandidateCondition $name $type $param $thresh)
                                  (CandidateCondition $name $type $param $thresh)))
      (if (== $conditions ())
          False
          (eval (allTrue $conditions)))))

(= (allTrue ()) True)
(= (allTrue $lst)
   (let* (
      (($head $tail) (decons-atom $lst))
      ((CandidateCondition $_ $type $param $thresh) $head)
      ($result (evalCondition $type $param $thresh))
   )
   (if $result (allTrue $tail) False)))



(= (generateCandidates)
   (let* (
      ($_ (clearCandidates))
      
      ($allCandidate (collapse (match &self (CandidateCondition $name $_t $_p $_h) $name)))
      
      ;; Add each candidate whose conditions are all satisfied
      ($_ (collapse
             (let $n (superpose $allCandidate)
                (if (candidateIsAvailable $n)
                    (addCandidate $n)
                    (empty)))))
   )
   (getCandidates)))
