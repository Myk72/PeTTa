;; MotivOS integration into OmegaClaw's loop.

;; PIPELINE ORDER (one cycle):
;;   refreshSignals        — extract signals from current loop state
;;   runAppraisal          — 6 appraisal dimensions → modulator updates
;;   runMotivationUpdate   — decay M + apply SignalEffect atoms
;;   runHomeostasis        — fire HomeostaticRule atoms if triggered
;;   motivationalDecision  — score candidates, select winner
;;   evolveGoalState       — G_next = (1-α)G + αG_proposed  (on current undecayed G)
;;   decayGoalState        — decay G toward GoalSpec baselines  (AFTER evolution)
;;   updateSelfModel       — EMA update of S metrics
;;   saveMotivationalState — persist X=(G,M,S) to ChromaDB



;; motivationContextBlock
;; Run the full motivation cycle and produce a text block for the LLM prompt.
(= (motivationContextBlock)
   (let* (
      ($signals (refreshSignals))
      ($appraisalRec (runAppraisal))

      ($_ (runMotivationUpdate))

      ($homeoFired (runHomeostasis))
      ($motResult (motivationalDecision))
      ((motivational-result $decision $allScores) $motResult)
      ((decision $selectedCand $mode $directive $score) $decision)

      ;; Goal evolution on current (undecayed) values, THEN decay
      ($_ (evolveGoalState))
      ($_ (collapse (decayGoalState)))

      ($hasError   (> (eval (string_length (eval (string-safe (repr (get-state &error)))))) 4))
      ($hasResults (hasContent (get-state &lastresults)))
      ($_ (updateSelfModel $hasError $hasResults))

      ($_ (saveMotivationalState))

      ($signalsStr    (eval (string-safe (repr $signals))))
      ($appraisalStr  (eval (string-safe (repr $appraisalRec))))
      ($goalStr       (eval (string-safe (repr (getGoals)))))
      ($antiGoalStr   (eval (string-safe (repr (getAntiGoals)))))
      ($modulatorStr  (eval (string-safe (repr (getModulators)))))
      ($selfModelStr  (eval (string-safe (repr (getSelfModel)))))
      ($scoresStr     (eval (string-safe (repr $allScores))))
      ($decisionStr   (eval (string-safe (repr $decision))))
      ($guidance      (directiveGuidance $directive))

      ;; Translate the winning candidate into a direct imperative for the LLM.
      ($instruction   (candidateInstruction $selectedCand))
   )
   (eval (py-str (
      " MOTIVATION_SIGNALS: "   $signalsStr
      " APPRAISAL: "            $appraisalStr
      " GOAL_STATE: "           $goalStr
      " ANTI_GOALS: "           $antiGoalStr
      " MODULATOR_STATE: "      $modulatorStr
      " SELF_MODEL: "           $selfModelStr
      " CANDIDATE_SCORES: "     $scoresStr
      " MOTIVATION_DECISION: "  $decisionStr
      " STEP_POLICY: "          $guidance
      " MOTIVATION_INSTRUCTION: " $instruction)))))


;; candidateInstruction
;; Translates the winning candidate name into a direct imperative statement
;; for the LLM so that MOTIVATION_DECISION becomes a binding directive.

(= (candidateInstruction $directive)
   (case $directive (
      (respond "REQUIRED: Respond to the user now. Your primary output MUST include a send command.")
      (retrieve-memory "REQUIRED: Query long-term memory before responding. Your primary output MUST include a query command.")
      (search-knowledge "REQUIRED: Search for relevant knowledge before responding. Your primary output MUST include a search or query command.")
      (execute-skill "REQUIRED: Execute the requested skill or task now. Your primary output MUST include the appropriate skill command.")
      (learn "REQUIRED: Capture and store new knowledge this cycle. Your primary output MUST include a remember command.")
      (self-improve "REQUIRED: Reflect on recent failures and update your approach. Consider using remember to store the lesson.")
      (defer "REQUIRED: Do not take irreversible action this cycle. Verify the situation first before acting.")
      (ask-clarification "REQUIRED: Ask the user a clarifying question. Your primary output MUST include a send command with a question.")
      ($other "REQUIRED: Act according to your current motivational state and the STEP_POLICY above.")
      
   ))
)



;; Extends OmegaClaw's standard context with the full MotivOS block.
;; The LLM sees scored candidates, the selected action, and a binding instruction.
(= (getContext)
   (let* (
      ($motivationText (motivationContextBlock))
      ($_ (println! (MOTIVATION-CONTEXT-BLOCK: $motivationText)))
   )
   (eval (string-safe
      (eval (py-str (
         "PROMPT: "                  (eval (getPrompt))
         " SKILLS: "                 (eval (getSkills))
         " OUTPUT_FORMAT: Output up to 5 raw lines. NO parentheses. NO quotes around arguments. NO conversational text."
         " Example format:"          (newline)
         " skillName1 arg1"          (newline)
         " skillName2 arg2"
         " LAST_SKILL_USE_RESULTS: " (eval (last_chars (get-state &lastresults) (maxFeedback)))
         " HISTORY: "                (eval (getHistory))
         " TIME: "                   (eval (get_time_as_string))
         " MOTIVATION: "             $motivationText
         )))))))


;; Entry point: initialize motivation, then start OmegaClaw's loop
(= (motivatedOmegaclaw)
   (let* (
      ($_ (initMotivationState))
      ($_ (initGoalState))
      ($_ (initSelfModel))
      ($_ (collapse (clearSignals)))
      
      ($_ (change-state! &new-msg-flag False))
      ; ($_ (tryRestoreOrInit))
   )
   (eval (omegaclaw))))