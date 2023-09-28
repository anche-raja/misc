const response = {
  // ... (your JSON data)
};

const formatIntoColumns = (response) => {
  if (
    !response.ResultsByTime ||
    !response.ResultsByTime[0] ||
    !response.ResultsByTime[0].Groups
  ) {
    return "Invalid data format";
  }

  const groups = response.ResultsByTime[0].Groups;

  // Header row
  let tableString =
    "Usage Type".padEnd(30) +
    "Blended Cost".padEnd(20) +
    "Unblended Cost".padEnd(20) +
    "Usage Quantity".padEnd(20) +
    "\n";
  tableString += "-".repeat(90) + "\n"; // Add a line for clarity

  // Data rows
  for (let group of groups) {
    const usageType = group.Keys[0];
    const blendedCost = group.Metrics.BlendedCost.Amount;
    const unblendedCost = group.Metrics.UnblendedCost.Amount;
    const usageQuantity = group.Metrics.UsageQuantity.Amount;

    tableString +=
      usageType.padEnd(30) +
      blendedCost.padEnd(20) +
      unblendedCost.padEnd(20) +
      usageQuantity.padEnd(20) +
      "\n";
  }

  return tableString;
};

console.log(formatIntoColumns(response));
