;; Motivational State Persistence
;;
;; Stores X=(G,M,S) in long-term ChromaDB memory so that the
;; motivational state survives session boundaries.
;;
;; Serialization format (stored as a remembered string):
;;   MOTIVOS_STATE_V1 time:<timestamp> G:<goals-repr> AG:<antigoals-repr>
;;                    M:<mods-repr> S:<self-repr>
;;
;; Restoration:
;;   On startup, query ChromaDB for the most recent MOTIVOS_STATE_V1 entry.
;;   Parse the retrieved string using Python bridge helpers and apply
;;   stored values back into &goal-space, &motivation-space, &self-model-space.
;;   Falls back to registry baselines if parsing fails.

(= (persistenceKey) "MOTIVOS_STATE_V1")


;; saveMotivationalState
;; Serialises the full X=(G,M,S) snapshot and stores it via remember.
(= (saveMotivationalState)
   (let* (
      ($timestamp (get_time_as_string))
      ($goals     (eval (string-safe (repr (getGoals)))))
      ($antiGoals (eval (string-safe (repr (getAntiGoals)))))
      ($mods      (eval (string-safe (repr (getModulators)))))
      ($self      (eval (string-safe (repr (getSelfModel)))))
      ($payload   (eval (py-str (
                     (persistenceKey) " time:" $timestamp
                     " G:" $goals " AG:" $antiGoals
                     " M:" $mods
                     " S:" $self))))
      ($_ (remember $payload))
      ($_ (println! ("Motivational state saved to long-term memory.")))
   ) saved))


;; restoreMotivationalState
;; Queries ChromaDB for the most recent motivational state snapshot.
;; Parses the retrieved string and applies stored numeric values into
;; the live &spaces. Falls back silently if no prior state exists.
(= (restoreMotivationalState)
   (let* (
      ($_ (println! ("Querying long-term memory for prior motivational state...")))
      ($results (eval (query (persistenceKey))))
      ($raw     (eval (string-safe $results)))
   )
   (if (hasContent $raw)
       (let* (
          ;; Parse the serialized state using the Python bridge.
          ;; py-call returns a list of (type name value) triples.
          ($parsed  (py-call (lib_llm_ext.parseMotivosState $raw)))
          ($_ (if (and (!= $parsed ()) (!= $parsed (Error)))
                  (let* (
                     ($_ (collapse
                            (let $entry (superpose $parsed)
                               (case $entry (
                                  ((goal $name $val)
                                    (replaceGoal $name $val))
                                  ((modulator $name $val)
                                    (replaceModulator $name $val))
                                  ((motive $name $val)
                                    (replaceMotive $name $val))
                                  ((self-metric $name $val)
                                    (replaceSelfMetric $name $val))
                                  ($_ (empty)))))))
                     ($_ (println! ("Prior motivational state successfully restored.")))
                  ) ())
                  (println! ("No prior motivational state found. Using registry defaults."))
                  ))
       ) ())
       (println! ("No prior motivational state found. Using registry defaults.")))))


;; tryRestoreOrInit
;; Called once during startup after default initialisation.
;; Attempts restore from a prior session; continues with registry
;; baselines as a safe fallback when nothing is found.
(= (tryRestoreOrInit)
   (let* (
      ($_ (println! ("Checking long-term memory for persisted motivational state...")))
      ($_ (restoreMotivationalState))
      ($_ (println! ("Startup restoration complete (defaults remain active as fallback).")))
   ) ()))
