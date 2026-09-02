/**
 * Find event in transaction receipt
 * @param {Object} receipt - Transaction receipt
 * @param {Object} contract - Contract with interface
 * @param {string} eventName - Event name to find
 * @returns {Object|undefined} - Parsed event or undefined
 */
function findEvent(receipt, contract, eventName) {
  for (const log of receipt.logs) {
    try {
      const parsed = contract.interface.parseLog(log);
      if (parsed && parsed.name === eventName) {
        return { ...parsed, args: parsed.args };
      }
    } catch {
      continue;
    }
  }
  return undefined;
}

/**
 * Find all events of a specific type in transaction receipt
 * @param {Object} receipt - Transaction receipt
 * @param {Object} contract - Contract with interface
 * @param {string} eventName - Event name to find
 * @returns {Array} - Array of parsed events
 */
function findAllEvents(receipt, contract, eventName) {
  const events = [];
  for (const log of receipt.logs) {
    try {
      const parsed = contract.interface.parseLog(log);
      if (parsed && parsed.name === eventName) {
        events.push({ ...parsed, args: parsed.args });
      }
    } catch {
      continue;
    }
  }
  return events;
}

module.exports = {
  findEvent,
  findAllEvents,
};
