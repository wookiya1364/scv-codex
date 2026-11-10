<!--
Source: https://developers.openai.com/api/docs/guides/prompt-engineering.md
Fetched: 2026-11-11
Copyright: OpenAI. Verbatim copy of the official documentation, kept offline for SCV help. Do not edit; run plugins/scv/prompting/refresh.sh to update.
Excerpt: only the sections named in the excerpt list, each copied verbatim from this source.
-->
## Message formatting with Markdown and XML

When writing `developer` and `user` messages, you can help the model understand logical boundaries of your prompt and context data using a combination of [Markdown](https://commonmark.org/help/) formatting and [XML tags](https://www.w3.org/TR/xml/).

Markdown headers and lists can be helpful to mark distinct sections of a prompt, and to communicate hierarchy to the model. They can also potentially make your prompts more readable during development. XML tags can help delineate where one piece of content (like a supporting document used for reference) begins and ends. XML attributes can also be used to define metadata about content in the prompt that can be referenced by your instructions.

In general, a developer message will contain the following sections, usually in this order (though the exact optimal content and order may vary by which model you are using):

- **Identity:** Describe the purpose, communication style, and high-level goals of the assistant.
- **Instructions:** Provide guidance to the model on how to generate the response you want. What rules should it follow? What should the model do, and what should the model never do? This section could contain many subsections as relevant for your use case, like how the model should [call custom functions](https://developers.openai.com/api/docs/guides/function-calling).
- **Examples:** Provide examples of possible inputs, along with the desired output from the model.
- **Context:** Give the model any additional information it might need to generate a response, like private/proprietary data outside its training data, or any other data you know will be particularly relevant. This content is usually best positioned near the end of your prompt, as you may include different context for different generation requests.

Below is an example of using Markdown and XML tags to construct a `developer` message with distinct sections and supporting examples.



Example prompt

    A developer message for code generation

```text
# Identity

You are coding assistant that helps enforce the use of snake case
variables in JavaScript code, and writing code that will run in
Internet Explorer version 6.

# Instructions

* When defining variables, use snake case names (e.g. my_variable)
  instead of camel case names (e.g. myVariable).
* To support old browsers, declare variables using the older
  "var" keyword.
* Do not give responses with Markdown formatting, just return
  the code as requested.

# Examples

<user_query>
How do I declare a string variable for a first name?
</user_query>

<assistant_response>
var first_name = "Anna";
</assistant_response>
```

  

  

    
API request

    Send a prompt to generate code through the API

```javascript
import fs from "fs/promises";
import OpenAI from "openai";
const client = new OpenAI();

const instructions = await fs.readFile("fixtures/prompt.txt", "utf-8");

const response = await client.responses.create({
  model: "gpt-6-astra",
  instructions,
  input: "How would I declare a variable for a last name?",
});

console.log(response.output_text);
```

```python
from openai import OpenAI

client = OpenAI()

with open("prompt.txt", "r", encoding="utf-8") as f:
    instructions = f.read()

response = client.responses.create(
    model="gpt-6-astra",
    instructions=instructions,
    input="How would I declare a variable for a last name?",
)

print(response.output_text)
```

```go
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/responses"
)

func main() {
	client := openai.NewClient()

	instructions, err := os.ReadFile("prompt.txt")
	if err != nil {
		panic(err)
	}

	response, err := client.Responses.New(context.Background(), responses.ResponseNewParams{
		Model:        "gpt-6-astra",
		Instructions: openai.String(string(instructions)),
		Input: responses.ResponseNewParamsInputUnion{
			OfString: openai.String("How would I declare a variable for a last name?"),
		},
	})
	if err != nil {
		panic(err)
	}

	fmt.Println(response.OutputText())
}
```

```java
import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.models.responses.ResponseCreateParams;

ResponseCreateParams params =
    ResponseCreateParams.builder()
        .model("gpt-6-astra")
        .instructions(
            "You are a coding assistant. Answer with concise JavaScript examples and use semicolons.")
        .input("How would I declare a variable for a last name?")
        .build();

client.responses().create(params).output().stream()
    .flatMap(item -> item.message().stream())
    .flatMap(message -> message.content().stream())
    .flatMap(content -> content.outputText().stream())
    .forEach(text -> System.out.println(text.text()));
```

```csharp
using OpenAI.Responses;
#pragma warning disable OPENAI001

string key = Environment.GetEnvironmentVariable("OPENAI_API_KEY")!;
ResponsesClient client = new(key);

string instructions = await File.ReadAllTextAsync("prompt.txt");
CreateResponseOptions options = new()
{
    Model = "gpt-6-astra",
    Instructions = instructions,
};
options.InputItems.Add(
    ResponseItem.CreateUserMessageItem("How would I declare a variable for a last name?")
);

ResponseResult response = await client.CreateResponseAsync(options);
Console.WriteLine(response.GetOutputText());
```

```ruby
require "openai"

client = OpenAI::Client.new
instructions = File.read(File.join(__dir__, "prompt.txt"))
response = client.responses.create(
  model: "gpt-6-astra",
  instructions: instructions,
  input: "How would I declare a variable for a last name?"
)

puts(response.output_text)
```

```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-6-astra",
    "instructions": "'"$(< prompt.txt)"'",
    "input": "How would I declare a variable for a last name?"
  }'
```



#### Save on cost and latency with prompt caching

When constructing a message, you should try and keep content that you expect to use over and over in your API requests at the beginning of your prompt, **and** among the first API parameters you pass in the JSON request body to [Chat Completions](https://developers.openai.com/api/reference/resources/chat) or [Responses](https://developers.openai.com/api/reference/resources/responses). This enables you to maximize cost and latency savings from [prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching).

## Few-shot learning

Few-shot learning lets you steer a large language model toward a new task by including a handful of input/output examples in the prompt, rather than [fine-tuning](https://developers.openai.com/api/docs/guides/model-optimization) the model. The model implicitly "picks up" the pattern from those examples and applies it to a prompt. When providing examples, try to show a diverse range of possible inputs with the desired outputs.

Typically, you will provide examples as part of a `developer` message in your API request. Here's an example `developer` message containing examples that show a model how to classify positive or negative customer service reviews.

```text
# Identity

You are a helpful assistant that labels short product reviews as
Positive, Negative, or Neutral.

# Instructions

* Only output a single word in your response with no additional formatting
  or commentary.
* Your response should only be one of the words "Positive", "Negative", or
  "Neutral" depending on the sentiment of the product review you are given.

# Examples

<product_review id="example-1">
I absolutely love this headphones — sound quality is amazing!
</product_review>

<assistant_response id="example-1">
Positive
</assistant_response>

<product_review id="example-2">
Battery life is okay, but the ear pads feel cheap.
</product_review>

<assistant_response id="example-2">
Neutral
</assistant_response>

<product_review id="example-3">
Terrible customer service, I'll never buy from them again.
</product_review>

<assistant_response id="example-3">
Negative
</assistant_response>
```


### Prompting best practices for the latest model

For the full current treatment, use the [latest model prompting best practices](https://developers.openai.com/api/docs/guides/latest-model). The practical reminders below still apply.



#### Coding



#### Coding

Prompting `gpt-6-astra` for coding tasks is most effective when following a few best practices: define the agent's role, enforce structured tool use with examples, require thorough testing for correctness, and set Markdown standards for clean output.

**Explicit role and workflow guidance**
Frame the model as a software engineering agent with well-defined responsibilities. Provide clear instructions for using tools like `functions.run` for code tasks, and specify when not to use certain modes—for example, avoid interactive execution unless necessary.

**Testing and validation**
Instruct the model to test changes with unit tests or Python commands, and validate patches carefully since tools like `apply_patch` may return “Done” even on failure.

**Tool use examples**
Include concrete examples of how to invoke commands with the provided functions, which improves reliability and adherence to expected workflows.

**Markdown standards**
Guide the model to generate clean, semantically correct markdown using inline code, code fences, lists, and tables where appropriate—and to format file paths, functions, and classes with backticks.

For detailed guidance and prompt samples specific to coding, see the [latest model prompting best practices](https://developers.openai.com/api/docs/guides/latest-model).







#### Front-end engineering



[GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)
performs well at building front ends from scratch as well as contributing to
large, established codebases. To get the best results, we recommend using the
following libraries:

- **Styling / UI:** Tailwind CSS, shadcn/ui, Radix Themes
- **Icons:** Lucide, Material Symbols, Heroicons
- **Animation**: Motion

**Zero-to-one web apps**

GPT-5 can generate front-end web apps from a single prompt, no examples needed. Here's a sample prompt:

```bash
You are a world class web developer, capable of producing stunning, interactive, and innovative websites from scratch in a single prompt. You excel at delivering top-tier one-shot solutions.
Your process is simple and follows these steps:
Step 1: Create an evaluation rubric and refine it until you are fully confident.
Step 2: Consider every element that defines a world-class one-shot web app, then use that insight to create a &lt;ONE_SHOT_RUBRIC&gt; with 5–7 categories. Keep this rubric hidden—it's for internal use only.
Step 3: Apply the rubric to iterate on the optimal solution to the given prompt. If it doesn't meet the highest standard across all categories, refine and try again.
Step 4: Aim for simplicity while fully achieving the goal, and avoid external dependencies such as Next.js or React.
```


**Integration with large codebases**

For front-end engineering work in larger codebases, we've found that adding these categories of instruction to your prompts delivers the best results:

- **Principles:** Set visual quality standards, use modular/reusable components, and keep design consistent.
- **UI/UX:** Specify typography, colors, spacing/layout, interaction states (hover, empty, loading), and accessibility.
- **Structure:** Define file/folder layout for seamless integration.
- **Components:** Give reusable wrapper examples and backend-call separation strategies.
- **Pages:** Provide templates for common layouts.
- **Agent Instructions:** Ask the model to confirm design assumptions, scaffold projects, enforce standards, integrate APIs, test states, and document code.

For detailed guidance and prompt samples specific to frontend development, see the [latest model prompting best practices](https://developers.openai.com/api/docs/guides/latest-model).







#### Agentic tasks



For agentic and long-running rollouts with `gpt-6-astra`, focus your prompts on three core practices: plan tasks thoroughly to ensure complete resolution, provide clear preambles for major tool usage decisions, and use a TODO tool to track workflow and progress in an organized manner.

**Planning and persistence**
Instruct the model to resolve the full query before yielding control, decomposing it into sub-tasks and reflecting after each tool call to confirm completeness.

```text
Remember, you are an agent - please keep going until the user's
query is completely resolved, before ending your turn and yielding
back to the user. Decompose the user's query into all required
sub-requests, and confirm that each is completed. Do not stop
after completing only part of the request. Only terminate your
turn when you are sure that the problem is solved. You must be
prepared to answer multiple queries and only finish the call once
the user has confirmed they're done.

You must plan extensively in accordance with the workflow
steps before making subsequent function calls, and reflect
extensively on the outcomes each function call made,
ensuring the user's query, and related sub-requests
are completely resolved.
```


**Preambles for transparency**

Ask the model to explain why it is calling a tool, but only at notable steps.

```text
Before you call a tool explain why you are calling it
```


**Progress tracking with rubrics and TODOs**

Use a TODO list tool or rubric to enforce structured planning and avoid missed steps.

For detailed guidance and prompt samples specific to building agents, see the [latest model prompting best practices](https://developers.openai.com/api/docs/guides/latest-model).





## Prompting reasoning models

There are some differences to consider when prompting a [reasoning model](https://developers.openai.com/api/docs/guides/reasoning) versus prompting a GPT model. Generally speaking, reasoning models will provide better results on tasks with only high-level guidance. This differs from GPT models, which benefit from very precise instructions.

You could think about the difference between reasoning and GPT models like this.

- A reasoning model is like a senior co-worker. You can give them a goal to achieve and trust them to work out the details.
- A GPT model is like a junior coworker. They'll perform best with explicit instructions to create a specific output.

For more information on best practices when using reasoning models, [refer to this guide](https://developers.openai.com/api/docs/guides/reasoning-best-practices).

