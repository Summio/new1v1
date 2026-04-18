from tortoise import BaseDBAsyncClient

RUN_IN_TRANSACTION = True


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `system_config` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `cfg_key` VARCHAR(64) NOT NULL UNIQUE COMMENT '配置键',
    `cfg_value` VARCHAR(255) NOT NULL COMMENT '配置值',
    `description` VARCHAR(255) COMMENT '说明',
    KEY `idx_system_conf_created_6590ff` (`created_at`),
    KEY `idx_system_conf_updated_bb6ff0` (`updated_at`)
) CHARACTER SET utf8mb4 COMMENT='系统配置（键值对）';
        """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `system_config`;"""


MODELS_STATE = (
    "eJztXVtznDgW/itd/ZTUZic0IC556zjZGW9N4inHmdmaZYsSILqZ0EC42OOd9X/fOqJpLg"
    "0Y6AuyzYvjIB0Mn4R0Lt85+mu+8S3iRj8sPXPth/N3s7/mHt6Q+btZpeXNbI6DIL8OF2Js"
    "uLQrzvsYURxiM56/m9nYjcib2dwikRk6Qez4HvTVEpEIhpZIIra0RLFEUUskpKpaYtucoi"
    "VoIQtaonBIXAbB14iEtEGFm1u+GcWh460OvE/iOd8Tosf+isRrAm/97/+8mc0dzyJ/kij7"
    "b/BNtx3iWiVQHAtuQK/r8X1Ar713Vpde/A/aF57S0E3fTTZe3j+4j9e+txNwvBiurohHQh"
    "wT+AtxmABWXuK6W1Az+NKHzbukT1mQsYiNExcQB+k9wLOLBey2l0zfg8FyvBje+a/5Cv7K"
    "31WeFwSZ5wRJQaIsI4VT3szm9JH2m+SH9IVzQNJbUVguf7z8fAMv6ofYTCcKXHigMjjGqR"
    "TFOwfYDAlAouN4H+gPOCaxsyH1UJclK5BbW9Efsl+qA5DB3TYC2YXTDUFIsHXluffbW7eg"
    "e3P56eOXm+WnX+BFNlH03aUILW8+QgtPr95Xrr6SXpeHY3eT2W+XNz/N4L+z368+f6QA+l"
    "G8CulfzPvd/D6HZ8JJ7Ouef6djq4BCdjVD6uFN4cNJAmvguJYlp3Edc1y3D19YDyPd91zH"
    "IzXLou+7BHsN62JRrjKmhu+7JxrGxj1JknhbS5DIS1qCZF7REpkY9rzT6LatgVdXP5cG8v"
    "1lZUX8/PXT+4/XrxZ0BKPvrhOXFsrCwohdVw9Cx6yBunH7KQs9vg0NgzlHNcN5wXG1KBsm"
    "oMxzkpaoompricotsJYohmXBfm7LWiIpgvkq7UQx6bxx8QtRFhVBEnf71e5K2za1j7Tjxa"
    "G/D/LFGocNkzkTqAAcxWEHgLeTtBe+tctRRSWSDYWDK6bREcYN/lN3ibeK1/N3M8RxLaD9"
    "ury++Gl5/QpxXGXp+bxt4tO2MrIxXkX7wP7zy9XnemCz/tVF3zHj2f9mrhPFZ8ZXUjgZkJ"
    "UJzNCFrCWKIikHLxOAQGmZyFB89Wn5ryrAFz9fva8u5HCD9xWw8S2OcdhnHucSo09kpAqi"
    "liDOtL9e/8zM/E23rAE6TEnwCCrMUee0zHFaotjWAlYLDqdbHxhTNizTyBYPnt8sKTUZMK"
    "3aKg4C916PYhwnUa8vqCI36DsaotjMA+JZMDr7I7xteYuDIPRvifU2JH8QE/76gM+K7/JV"
    "8c0fFTRVlikKWf9PqijH2BclIwFcDwZVZ17wVxSSW4fcDTL6KqKMDTAy8IJqqspLH2BYSf"
    "SQ4Mj3+qyTe4KjKxwSb/Gw84EhggQwTZBEOGY0DxwEehKRUO/rgKwIHscEfD6uSHD02ltH"
    "787za2Dz2x0OLX2vxef9Wq9lhvL+2Fx55Ma/8tJl7tKLYuzVGuOZtz31VbM4KFt886v5nw"
    "jx3c5XXp1xvqdbxCWpW+Ni+eVi+eHj/KEEcxlVaNrwm+oV7OEVfS14OniWHWJObdgicB6J"
    "WWw7PBawaMZnCiNMYYTJ3TyFEaZxPTiMEOB43Ud/zPqfzb6uVxuXv1xC6JmAtmgr4hBtca"
    "F20RYXarO2SNvK2uKGxGvfqgf0o5ds9pSREri59Mjw7mxoU+TB0DJU+N1CQ3CWOqAsNWIs"
    "VRGOks0Gh/d95mxBhClcD4sT8KiTRwi1uIRQxzhBM7QNcYJRloM8RDAqnAcZNr2084I7wH"
    "eJjgOnZuw+Ye/+xoefHQ2ha98lT8wKok+uV+yQ7D1C4lL1I7cYtzD5IUX5G7nfQZhq+7sB"
    "2DbhwNm2xOvQT1brIuSNltab2VyvWggPjxhUqQlaa1TtrNM2wyq3hR+ngy2DYAYeUwi5S7"
    "wgZ/QtSZJIFh7OW2d/m5WDnLXUsCPdc7LvJvtusgMm+24a18Ptu7VfRxFrMfAygeOodAMX"
    "RRoXEGFjkAUMcQFbfqUlsiQbYPAhBMYfZYwJtvyajXBqgKPozg+tftZ0LnMqFbpPcM2UtE"
    "RWuAWlgWEuvTQI3wWvdLGueaXZuoa2MsSeY36jv/eAuCgzfqxLEpCWyKo9KL4ldJmzQvOc"
    "haaJqXTieOGKeBbpBWkucTZI5xExQ0L36wqsG+yStzah/xQ69f36O7nWWjxre7Aa2M3M1o"
    "4M3ILE+ei3teRbVTQWsFVxSEtEG6laoiqqNS7Vtj/D6kBu1ePTdJ9a5fnhBlNGegXTtOGt"
    "gT2PFTaVE+l5MlY/Pn4uxxgfXySgfKWkW5lgqWits8TQt0P/v8TT+68R+4KnWir2BqB2pU"
    "ALw6BcGIGdlcL0HS/qk/mQ9R971V0ArxYRbsEOlpaDN75n9YGzKDI2oiKdnbLN0OzcfsED"
    "gK2RHBnf4tefYz0uvgb2BrAMy1LjWwomLAKyqiyYpBi6OIp11185Xl/XW1mSyfQGJHKk7L"
    "l5abzdUwUEC2Y8VSD1IPRtJw16VRTQ7Q0ySuQ1hMRgnJrZkDuV9FwT5uA44ENf+mJiOfHP"
    "/qo23Ja1tcfboJe77TWxGado1xTtYmEhnqJdLzba1Zio0bgiHj1D4wBuWM6MuPwwjrYPaP"
    "QNsBRlzpd1WeMULBNPkMhZw0MtktiFtSg20xbFPWaobyVuL2BzifOFButxRTzYTApnW1oi"
    "YR6sKBnJbODKJh+0K7Ilmq0ANToUe9iMPUnAtY3O3DBpT05hHgTtQQzm40ezWGPdD8H0MP"
    "Y9j1Anui1qodui1x2DWo27f2NM63Sb/98XtTsXb0haInHUT6Vwi3G2/5BEge9FRM9U144w"
    "7smN7UgVTUgmJqpY9DaBI1UAB5Roi9YmGsmhGpLvCYliHYf9KvJU5ZipzFNcE5Bg0tVW5t"
    "iszLObqIZv3fdDvyLIDvy2BSwYySIp8KBHSIQd+M+XDtHq7bvArntNTODa1fj7Cq2tHj9a"
    "1S3MO3aouVqss6YYBnjEbbSnhrR2nByEk4NwciRNDsJpXA92EMICPqCWS0lsdD9hSsJCAj"
    "EO8BmeZd2sAE+GAU9YAV5RcC3wr4rEuNcsD8PZaZ8nKqnneysf/gXqtPXWxo5LrLewnvpJ"
    "zAYf1ErCXYy9K9WrIDI21augjGYWtGxDCo5q8SNZzrEfY1e3SR/PRElmZEwlDpYIxRLUdP"
    "UYl9hFPGsAsassNTqxK+XKSTKyDyd2deJ1tdC6XrNj7H4gQVxn5tLrrQaulfWY6CyTtTpZ"
    "q2xaNZO1+kKs1d65rkelYQxP3VY5ooDGCD8P42GcQC8nkdkH06z/6LoOUqG8kWQShRniuh"
    "Nt695Y/ZPeCoIMZL0ptkTPR+E5LVElScyqSYEjnqVMNz+sTS5u1JB2/cfNa5MEFaKDRLHH"
    "MXYCHBIv7scMLMmMC5/MC1JxVT0nPZAhk+bC9aMkJE2WTdb8qIFjFjpOds5k50x2Dpv68G"
    "TnvBA7B5Lvo7iudELz6QoFkdHjQun+LBIijKPewAMRz8Lpi3eNNpSERscQGYgbE0OX3BK3"
    "B3y7/iNr1pZNqxxg6cWphD86dq2Xm15vVQJXWY8O/C1ZFUz4wiUod7AQwZdh7/PrWjtOmi"
    "K7muK4LrZD9pzCdDvMx3ac0FfJL2T2iypm/ccvgVhCVbKBU6twMkv15foeRHzyM4h70JbY"
    "OGU4ul1hPQndXiyYgszInuAvv/64pOU54ahsJBgsTU4oZmbGzu2AQ8lzuZO5g/cR3s3d1i"
    "JocDKrJBvS2I5ghvSuZip9ofVRHawnlb64OLdS6Zs7TqoYu6rY5LR7Ds6dyWn3Qpx2ES1b"
    "3JvRXRIbXSdFAhSJVGnercJxiG0SfUhM4twOAL0iODrskoBpIThwm7IPO1VV+kJeEDof7/"
    "hxs/YJIN3XJVMSYsyFwJhjhjnnQXdYx/QeMGJ4fSJeUmdy0eutxtYm6zHRHSbLabKc2NSw"
    "J8vpeY4rY7TuQ/JfBcvMiuiwxusOyQaH3/rVdMkkmCnmItqQcCkjqK2PDAQKj2EgNmvpgE"
    "6RQjb4tOvCDUan1xfntmzSauWyMuhg5rb9PcNdbpzZ8qjB1FMhmsdShyC66BSrWrTEqmgb"
    "2zX4Bq3ChxXhOwmuU4rCy01RyKfmWBWMnUhfO5ZFvP4R6FzujBHoxmBnMQStSiqnJQoybZ"
    "ZykUx/E/geqSOdNq+iJSEGnHXEFKlvSWJm/fxGSIDd/hyKkhwDHApkICiQYwkGS5M2JJYT"
    "ErPXnC3KjK5VqQta29RQ4VhkcbEYdd6ezzFaGEHfJTrYDjVljD5h7/7Gh597pkf9OTfXfl"
    "ph/Uy50QcfcpM5g9N4x/57hHCyD7Hy5h1Ofkhx/kbudyCmesNuCLZN1CxLm+J16CerdQl1"
    "OiO8bfou/W6WXy6WH6ibRK96Zx9a/dnXxFzjcEWuqAZY49gud2j1cIfbrvpOnezCKEILEY"
    "wTDiI2ioFpBdtaRlFzx8kvPvnFJ//p5BefxvV0p/e0LYrP4gCfM9Ms6B6pe34fJbgoM3Z9"
    "mXwHhp82IyfR4I2f9MrAzAXGp1cUFZz05OTxz/Z9LsVKA+xYb00wRFwoUxoSO4GypWzEzQ"
    "J8r5tr7Hl12a9t3vCS2OhmsYTAXSYSCxZgQsv4cEh4N7v78y12nQDfs4K2M0RtKYixdshv"
    "EffpYN8xaGHU9q+znrc+gRajOesx0cIm83cyf1lYbCbz96WMK2O0sAOsMdWC4wB5mWePFf"
    "Zkq30WQT3sYNCjJXqPEew5Vpwno8g/9ThP9h7VOE8lKFYO9hQiOtVgTyEOdFCwZ3+TwoFz"
    "jIFbBs5zGLfta9QO2w6p8qjhwOk/aDj9OwPHjPpS4T7HGLmvURqHe+pDl71H3djVjVvBId"
    "1t4HaoHzG0+uU+isnmwvdsZ1VnG5baW23EiPYEuLKuXSo1mDYckUQsu1gLS0tsm6MlbHmS"
    "+RqRYav0uloTdR16m8konYzSyXiZjNJpXA8/MNFe0d2rD8UzFxnbNC1uGrBdsBEoBIBusZ"
    "v0svZLQuMTZ4vIwhY8yNxHqIu9j1CzwQ9t+xZ/9qQ9Df+C2Pj2v2HDIRQSR0ZFlpEQB9XB"
    "a9TYTDdvVl9BuZ5CHJM2OWmTDGsdkzb5ghh+fcMcRZmx9cmc4MdeqAO7Du5FltoJnEjZ6V"
    "6ETYVTXAHPIUgKXZAUmpGEpsrRuBvs9CJD7QTGnp8qh4mWyIYxLC1I7ZQWpLakBan7jKe1"
    "7/X63ncCY09LGQmQYW1YzDD1ouhuWy63O00vlxndpkGGKWmJrHDDZievdJmdvNI8O6HtKR"
    "Ws3puqXepVS7bJsZd36UR6lAQkzOyxfliXRBk4LrJcH1zAUIhBgcIhBMuw/uKFlsgiJ0Ef"
    "pLA0Di6OYt31V47XV7EuS56Fhtq9nqjMQZFvkYPdT6LFW2xIDnhpjNSyIyzoWU6iIDEoIe"
    "GIA/rcz7ospzNPmcyPZzJXuAmd05kL4fiDYu455bvRS/mbE6+tEN8tg4Da7nvuynKHVr/l"
    "3barjnd9O8TdJcHitEQW4MgDGQkC9SPvpUe1dpy8nZO3c/KKTd7OaVynfOanks/8pDNvi1"
    "sxK5m3Bva+9a7DXxIa3dmkimD6KYposleGH5smzL+eGfhlKaYAVizwhAxNxT8+wCHBW8Oi"
    "V5mvgtDo8MryAlxMhkrYC5A8m8T80DdJFNGc/D+ICX+eDU9/9lxDUsUrsozliyOVEzPf6E"
    "vzzjFCplqS0DHXdf6JbUurYwLnfZihVD0jD8OBKlyz7+CWhFFPTmRBZGTCaXcUT08whU+j"
    "j9aWdn+aAJ6kwK3pe3Ft1eDmoxoKIged1TACoA/N+B3tWIZRN5aH/wNuzPBh"
)
