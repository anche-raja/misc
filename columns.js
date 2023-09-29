const data = {
    //... (Your provided JSON data)
};

const displayAsTable = (data) => {
    const colWidths = [
        "Date Start".length,
        "Date End".length,
        "Usage Type".length + 5,
        "Blended Cost".length,
        "Unblended Cost".length,
        "Usage Quantity".length,
        "Unit".length
    ];
    const header = [
        "Date Start".padEnd(colWidths[0]),
        "Date End".padEnd(colWidths[1]),
        "Usage Type".padEnd(colWidths[2]),
        "Blended Cost".padEnd(colWidths[3]),
        "Unblended Cost".padEnd(colWidths[4]),
        "Usage Quantity".padEnd(colWidths[5]),
        "Unit".padEnd(colWidths[6])
    ];
    const divider = header.map(title => "-".repeat(title.length)).join(" | ");
    
    console.log(header.join(" | "));
    console.log(divider);

    data.ResultsByTime.forEach(timePeriod => {
        const startDate = timePeriod.TimePeriod.Start;
        const endDate = timePeriod.TimePeriod.End;

        timePeriod.Groups.forEach(group => {
            const usageType = group.Keys[0].padEnd(colWidths[2]);
            const blendedCost = parseFloat(group.Metrics.BlendedCost.Amount).toFixed(2).padEnd(colWidths[3]);
            const unblendedCost = parseFloat(group.Metrics.UnblendedCost.Amount).toFixed(2).padEnd(colWidths[4]);
            const usageQuantity = parseFloat(group.Metrics.UsageQuantity.Amount).toFixed(2).padEnd(colWidths[5]);
            const unit = group.Metrics.UsageQuantity.Unit.padEnd(colWidths[6]);

            console.log([startDate, endDate, usageType, blendedCost, unblendedCost, usageQuantity, unit].join(" | "));
        });

        console.log(divider);  // print a divider after each day for better visual separation
    });
};

displayAsTable(data);
