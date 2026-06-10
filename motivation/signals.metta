;; Signal extraction from OmegaClaw loop state.


!(bind! &new-msg-flag (new-state False))


(= (hasContent $value)
   (> (eval (string_length (eval (string-safe $value)))) 2))

(= (clearSignals)
   (clearSpace &signal-space))

(= (addSignal $kind $strength)
   (add-atom &signal-space (signal $kind $strength)))

(= (getSignals)
   (collapse (match &signal-space (signal $kind $strength) (signal $kind $strength))))


;; refreshSignals
;; Extract signals from current OmegaClaw state.
(= (refreshSignals)
   (let* (
      ($_ (collapse (clearSignals)))
      ;; Read OmegaClaw state (interface contract)
      ($msg        (get-state &prevmsg))
      ($activeTask (get-state &active-task))
      ($results    (get-state &lastresults))
      ($error      (get-state &error))
      ($isNewMsg   (get-state &new-msg-flag))
      ($hasMsg     (hasContent $msg))
      ($hasResults (hasContent $results))
      ($hasError   (> (eval (string_length (eval (string-safe (repr $error))))) 4))
      ($resultsLen (eval (string_length (eval (string-safe $results)))))
      ;; Only update the streak on active (new-message) cycles.
      ;; Idle cycles reset the streak so a single old error doesn't compound.
      ($_ (if $isNewMsg
              (if $hasError
                  (change-state! &failure-streak (+ (get-state &failure-streak) 1))
                  (change-state! &failure-streak 0))
              (change-state! &failure-streak 0)))
      ($failureStreak (get-state &failure-streak))

      ;; 1. Repeated failure: multiple consecutive errors on active cycles
      ($_ (if (and $isNewMsg (and (> $failureStreak 1) $hasError))
              (addSignal repeated-failure 0.85)
              _))

      ;; 2. Single failure (first error on an active cycle)
      ($_ (if (and $isNewMsg (and $hasError (<= $failureStreak 1)))
              (addSignal failure 0.80)
              _))

      ;; 3. Task drift — only on a new message when topic changed
      ;;    Compare the incoming message to the previously stored active task.
      ($_ (if (and $isNewMsg (and (hasContent $activeTask) (!= $msg $activeTask)))
              (addSignal task-drift 0.45)
              _))

      ;; 4. Ambiguity — new message with no results and no error
      ($_ (if (and $isNewMsg (and (not $hasResults) (not $hasError)))
              (addSignal ambiguity 0.60)
              _))

      ;; 5. Progress made — recent results are short (quick success)
      ($_ (if (and $hasResults (and (<= $resultsLen 20) (not $hasError)))
              (addSignal progress-made 0.40)
              _))

      ;; 6. Stalled progress — new message, no results, no error
      ($_ (if (and $isNewMsg (and (not $hasResults) (not $hasError)))
              (addSignal stalled-progress 0.35)
              _))

      ;; 7. User waiting — any cycle where there is an active pending message
      ($_ (if $hasMsg
              (addSignal user-waiting 0.30)
              _))

      ;; 8. Semantic extraction — only on new messages (avoid re-calling LLM on idle)
      ($_ (if $isNewMsg
              (collapse (let* (($prov (provider))
                               ($semStr (py-call (lib_llm_ext.extractSemantics $prov $msg)))
                               ($semList (catch (sread $semStr))))
                          (if (and (!= $semList ()) (!= $semList (Error)))
                              (let $s (superpose $semList)
                                   (add-atom &signal-space $s))
                              (empty))))
              _))
              
      ;; Track the active task (update only when a new message arrived)
      ($_ (if $isNewMsg
              (change-state! &active-task $msg)
              _))
   )
   (getSignals)))
