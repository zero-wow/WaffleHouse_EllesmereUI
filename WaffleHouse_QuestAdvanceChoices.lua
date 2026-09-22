local _, addon = ...

-- Curated quest-advance choices.  Each key is a stable questID and each inner
-- key is the normalized text returned by C_GossipInfo.GetOptions().  We do
-- not store speculative branches: an entry is added only after the active
-- quest and the exact advancing choice have both been observed/verified.
--
-- Wowhead verifies 93396 as Midnight's "Bursting at the Seams" and its
-- objective is to help Kifaan support his sister. The precise option text was
-- captured from the in-game quest-advance dialogue, not inferred from prose.
addon.QuestAdvanceChoices = {
    [93396] = {
        ["encourage kifaan to talk to his sister"] = true,
    },
}
