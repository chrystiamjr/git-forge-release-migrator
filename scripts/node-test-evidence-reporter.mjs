// Node's test runner invokes this reporter; output is parsed as data, never executed by publication jobs.
export default async function* report(source) {
  for await (const event of source) {
    if (event.type === 'test:pass' || event.type === 'test:fail') yield `${JSON.stringify(event)}\n`;
  }
}
