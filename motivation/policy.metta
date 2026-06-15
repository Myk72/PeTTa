;; Shared helpers for the decision pipeline.


;; sumList
;; Left-fold sum of a numeric list.
(= (sumList () $acc) $acc)
(= (sumList $lst $acc)
   (let* (
      (($head $tail) (decons-atom $lst))
   )
   (sumList $tail (+ $acc $head))))


;; directiveGuidance
;; Looks up the DirectiveText atom for a given directive symbol.
;; Falls back to a generic message if no atom is registered.
(= (directiveGuidance $directive)
   (let $texts (collapse (match &self (DirectiveText $directive $text)
                   $text))
      (if (== $texts ())
          "Work normally while respecting current motivation state."
          (car-atom $texts))))
