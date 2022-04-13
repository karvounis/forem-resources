I am glad to announce that I have just released a Terraform provider for Forem! This provider is my small contibution to this amazing open-source project. You can find it [here](https://github.com/karvounis/terraform-provider-forem).

## TL;DR

Manage your Forem resources using code! Forem as Code (FaC) following the [Infrastructure as Code](https://www.ibm.com/cloud/learn/infrastructure-as-code) (IaC) concept.

## Need

[Forem](https://github.com/forem/forem) is a great software project and the platform that powers [dev.to](https://dev.to/). When I published my first article in `dev.to`, I found it very easy to navigate through the browser interface of Forem, create, write, and edit the article.

However, while I was writing the second article, I realised that there are a lot of similarities between them and that certain things can be automated. I also realised that the more articles you publish, the harder their maintenance is going to get. Using just the browser does not scale well and there is certainly room for automation.

## API

Forem has an [API](https://developers.forem.com/api) that you can use in order to create and update articles, listings and a few other resources. Instead of using the browser, you can send HTTP requests to the `api` endpoint of the Forem installation and read, create or update the resources you need.

### Example

You can visit in your browser <https://dev.to/karvounis/basic-traefik-configuration-tutorial-593m> or send the following `curl` request

```bash
curl https://dev.to/api/articles/karvounis/basic-traefik-configuration-tutorial-593m
```

## How to use it

The provider requires two arguments:

- `api_key` (String) API key to be able to communicate with the FOREM API. Can be specified with the `FOREM_API_KEY` environment variable.
- `host` (String) Host of the FOREM API. You can specify the `dev.to` or any other Forem installation. Can be specified with the `FOREM_HOST` environment variable. Default: `https://dev.to/api`.

In order to generate an API key, go to `Settings -> Account -> DEV Community API Keys`, give it a proper description and press the `Generate API Key` button.

### Forem Articles through Terraform

You can create a new Forem article using the examples shown [here](https://registry.terraform.io/providers/karvounis/forem/latest/docs/resources/article#example-usage). In this example, both `example_file` and `example_full` articles use the same tags that are defined in the `locals` block.

Imagine having way more articles maintained by Terraform and you need to remove a specific tag from all of them. With this provider, you can just remove that tag from the list, re-run the plan and Terraform will be smart enough to understand the difference and remove this tag from all the articles. By doing that, we saved ourselves a lot of clicks!

## Conclusion

I really hope that this provider is going to help all people using **Forem**. In fact, this very article has been generated using this provider! You do not believe me? Check the Terraform [article resource](https://github.com/karvounis/forem-resources/blob/master/articles_forem.tf#L1-L7) and the actual [Markdown file](https://github.com/karvounis/forem-resources/blob/master/files/forem/terraform_provider_intro.md)! :wink:

Any contributions to the provider are welcome and I would appreciate any feedback in the comments section!

## Useful links

- [Github](https://github.com/karvounis/terraform-provider-forem)
- [Project Roadmap](https://github.com/karvounis/terraform-provider-forem/projects/1)
- [Go Forem client](https://github.com/karvounis/dev-client-go)
- [Terraform registry](https://registry.terraform.io/providers/karvounis/forem/latest)
